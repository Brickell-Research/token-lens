import { isHumanPrompt, isTaskNotification, withToken } from "../token";
import type { Node } from "../types";

export class Reshaper {
  private pendingRoots: Node[] = [];

  reshape(roots: Node[]): Node[] {
    const nodes = this.collapseStreaming(roots);

    this.pendingRoots = [...nodes];
    const result: Node[] = [];

    while (this.pendingRoots.length > 0) {
      const batch = this.pendingRoots;
      this.pendingRoots = [];
      result.push(...batch.flatMap((node) => this.processRoot(node)));
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Collapse streaming chains: thinking -> text -> tool_use events emitted by
  // Claude Code for a single API response, detected by identical input usage.
  // ---------------------------------------------------------------------------

  private collapseStreaming(nodes: Node[]): Node[] {
    return nodes.flatMap((node) => {
      if (this.isStreamingIntermediate(node)) {
        return this.collapseStreaming(node.children);
      } else {
        return [{ ...node, children: this.collapseStreaming(node.children) }];
      }
    });
  }

  private isStreamingIntermediate(node: Node): boolean {
    if (node.token.role !== "assistant") return false;
    if (node.children.length !== 1) return false;

    const child = node.children[0];
    if (child.token.role !== "assistant") return false;

    const t = node.token;
    const c = child.token;

    // Prefer requestId equality (same API call); fall back to token count fingerprint
    if (t.requestId && c.requestId) {
      return t.requestId === c.requestId;
    }

    return (
      t.inputTokens === c.inputTokens &&
      t.cacheReadTokens === c.cacheReadTokens &&
      t.cacheCreationTokens === c.cacheCreationTokens
    );
  }

  // ---------------------------------------------------------------------------
  // Re-root the tree around human prompt nodes. Human prompts become roots;
  // the linear assistant chain beneath them becomes a flat list of siblings.
  // ---------------------------------------------------------------------------

  private processRoot(node: Node): Node[] {
    const t = node.token;

    if (isHumanPrompt(t)) {
      const siblings = this.flattenThread(node.children, 0, false);
      return [{ ...node, children: siblings }];
    } else if (t.role === "user") {
      // Tool-result-only user at root level -- hoist children
      return node.children.flatMap((c) => this.processRoot(c));
    } else {
      // Orphan assistant root (no human prompt ancestor)
      return this.flattenThread([node], 0, false);
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

  private flattenThread(nodes: Node[], prevInput: number, throughAssistant: boolean): Node[] {
    return nodes.flatMap((node) => {
      const t = node.token;

      if (t.role === "user" && !isHumanPrompt(t)) {
        // Tool-result user -- transparent, recurse into children
        return this.flattenThread(node.children, prevInput, throughAssistant);
      } else if (t.role === "assistant") {
        const marginal = Math.max(t.inputTokens - prevInput, 0);
        const compaction = prevInput > 0 && t.inputTokens < prevInput * 0.5;

        const sidechain = node.children.filter((c) => c.token.isSidechain);
        const chain = node.children.filter((c) => !c.token.isSidechain);

        // Flatten the response chain inside task-notification sidechains so
        // they don't create arbitrarily deep linked-list nesting.
        const flattenedSidechain = sidechain.map((sc) => {
          if (isTaskNotification(sc.token)) {
            return {
              ...sc,
              children: this.flattenThread(sc.children, 0, false),
            };
          }
          return sc;
        });

        const updated: Node = {
          ...node,
          token: withToken(t, {
            marginalInputTokens: marginal,
            isCompaction: compaction,
          }),
          children: flattenedSidechain,
        };

        return [updated, ...this.flattenThread(chain, t.inputTokens, true)];
      } else if (throughAssistant) {
        // Human prompt after an assistant -- genuine new turn, hoist to top level.
        this.pendingRoots.push(node);
        return [];
      } else {
        // Human prompt before any assistant (consecutive user messages, e.g. an
        // image attachment). Treat as transparent and continue into its children.
        return this.flattenThread(node.children, prevInput, false);
      }
    });
  }
}
