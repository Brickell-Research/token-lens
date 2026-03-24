import { isHumanPrompt, isTaskNotification, withToken } from "../token";
import type { Node } from "../types";

export function reshape(roots: Node[]): Node[] {
  const nodes = collapseStreaming(roots);
  let pending = [...nodes];
  const result: Node[] = [];

  while (pending.length > 0) {
    const batch = pending;
    pending = [];
    result.push(...batch.flatMap((node) => processRoot(node, pending)));
  }

  return result;
}

// ---------------------------------------------------------------------------
// Collapse streaming chains: thinking -> text -> tool_use events emitted by
// Claude Code for a single API response, detected by identical input usage.
// ---------------------------------------------------------------------------

function collapseStreaming(nodes: Node[]): Node[] {
  return nodes.flatMap((node) => {
    const { token: t, children } = node;
    if (
      t.role === "assistant" &&
      children.length === 1 &&
      children[0].token.role === "assistant" &&
      sameApiCall(t, children[0].token)
    ) {
      return collapseStreaming(children);
    }
    return [{ ...node, children: collapseStreaming(children) }];
  });
}

function sameApiCall(t: Node["token"], c: Node["token"]): boolean {
  // Prefer requestId equality (same API call); fall back to token count fingerprint
  return t.requestId && c.requestId
    ? t.requestId === c.requestId
    : t.inputTokens === c.inputTokens &&
        t.cacheReadTokens === c.cacheReadTokens &&
        t.cacheCreationTokens === c.cacheCreationTokens;
}

// ---------------------------------------------------------------------------
// Re-root the tree around human prompt nodes. Human prompts become roots;
// the linear assistant chain beneath them becomes a flat list of siblings.
// ---------------------------------------------------------------------------

function processRoot(node: Node, pending: Node[]): Node[] {
  const t = node.token;

  if (isHumanPrompt(t)) {
    const siblings = flattenThread(node.children, 0, false, pending);
    return [{ ...node, children: siblings }];
  } else if (t.role === "user") {
    // Tool-result-only user at root level -- hoist children
    return node.children.flatMap((c) => processRoot(c, pending));
  } else {
    // Orphan assistant root (no human prompt ancestor)
    return flattenThread([node], 0, false, pending);
  }
}

// ---------------------------------------------------------------------------
// Flatten a linear user->assistant->user(tool_result)->assistant chain into
// a flat list of assistant siblings, computing marginalInputTokens deltas.
// Sidechain children stay nested under the assistant that spawned them.
//
// throughAssistant: tracks whether we've passed at least one assistant turn.
// A human prompt encountered BEFORE any assistant (e.g. a screenshot attached
// to the same user turn) is treated as transparent -- we recurse into its
// children rather than hoisting it. A human prompt encountered AFTER an
// assistant is a genuine new conversational turn and gets hoisted.
// ---------------------------------------------------------------------------

function flattenThread(nodes: Node[], prevInput: number, throughAssistant: boolean, pending: Node[]): Node[] {
  return nodes.flatMap((node) => {
    const t = node.token;

    if (t.role === "user" && !isHumanPrompt(t)) {
      // Tool-result user -- transparent, recurse into children
      return flattenThread(node.children, prevInput, throughAssistant, pending);
    } else if (t.role === "assistant") {
      const marginal = Math.max(t.inputTokens - prevInput, 0);
      const compaction = prevInput > 0 && t.inputTokens < prevInput * 0.5;

      const sidechain = node.children.filter((c) => c.token.isSidechain);
      const chain = node.children.filter((c) => !c.token.isSidechain);

      // Flatten the response chain inside task-notification sidechains so
      // they don't create arbitrarily deep linked-list nesting.
      const updated: Node = {
        ...node,
        token: withToken(t, {
          marginalInputTokens: marginal,
          isCompaction: compaction,
        }),
        children: sidechain.map((sc) =>
          isTaskNotification(sc.token)
            ? { ...sc, children: flattenThread(sc.children, 0, false, pending) }
            : sc,
        ),
      };

      return [updated, ...flattenThread(chain, t.inputTokens, true, pending)];
    } else if (throughAssistant) {
      // Human prompt after an assistant -- genuine new turn, hoist to top level.
      pending.push(node);
      return [];
    } else {
      // Human prompt before any assistant (consecutive user messages, e.g. an
      // image attachment). Treat as transparent and continue into its children.
      return flattenThread(node.children, prevInput, false, pending);
    }
  });
}
