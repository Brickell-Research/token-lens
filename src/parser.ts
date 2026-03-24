import { readFileSync } from "node:fs";
import {
  createToken,
  humanText,
  isHumanPrompt,
  isTaskNotification,
  toolUses,
  withToken,
} from "./token";
import type { Node, RawEvent, Token } from "./types";

function getOrInit<K, V>(m: Map<K, V[]>, k: K): V[] {
  let a = m.get(k);
  if (!a) {
    a = [];
    m.set(k, a);
  }
  return a;
}

export class ParseError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ParseError";
  }
}

export class Parser {
  private filePath: string;

  constructor(filePath: string) {
    this.filePath = filePath;
  }

  parse(): Node[] {
    const rawEvents = this.readRawEvents();
    const tokens = rawEvents
      .map((e) => createToken(e))
      .filter((t) => t.type === "user" || t.type === "assistant");
    const tree = this.buildTree(tokens, rawEvents);
    this.attachSubagentTurns(tree, rawEvents);
    this.attachTaskNotifications(tree);
    return tree;
  }

  private buildTree(tokens: Token[], rawEvents: RawEvent[]): Node[] {
    const index = tokens.reduce(
      (acc, t) => {
        if (t.uuid) acc[t.uuid] = { token: t, children: [] };
        return acc;
      },
      {} as Record<string, Node>,
    );

    // Build a parent map covering ALL raw events (including filtered progress/tool-result
    // events) so we can walk through gaps when a token's direct parent was filtered out.
    const rawParent: Record<string, string | undefined> = {};
    for (const e of rawEvents) {
      if (e.uuid) rawParent[e.uuid] = e.parentUuid;
    }

    const roots: Node[] = [];
    Object.values(index).forEach((node) => {
      let parentUuid: string | null | undefined = node.token.parentUuid;
      // Walk up through filtered events to find the nearest indexed ancestor.
      let hops = 0;
      while (parentUuid && !index[parentUuid] && hops < 20) {
        parentUuid = rawParent[parentUuid];
        hops += 1;
      }
      const parent = parentUuid ? index[parentUuid] : undefined;
      if (parent) {
        parent.children.push(node);
      } else {
        roots.push(node);
      }
    });

    return roots;
  }

  // Extract subagent turns from agent_progress events and attach them as
  // isSidechain children of the assistant turn that invoked the Agent tool.
  private attachSubagentTurns(tree: Node[], rawEvents: RawEvent[]): void {
    const progressByToolUse = new Map<string, RawEvent[]>();
    for (const evt of rawEvents) {
      if (evt.type !== "progress") continue;
      if (evt.data?.type !== "agent_progress") continue;
      if (evt.data?.message?.type !== "assistant") continue;
      const toolUseId = evt.parentToolUseID;
      if (!toolUseId) continue;
      getOrInit(progressByToolUse, toolUseId).push(evt);
    }

    if (progressByToolUse.size === 0) return;

    // Index all nodes by their tool_use content IDs
    const toolUseNode: Record<string, Node> = {};
    this.flattenNodes(tree).forEach((node) => {
      toolUses(node.token).forEach((tu) => {
        if (tu.id) toolUseNode[tu.id] = node;
      });
    });

    progressByToolUse.forEach((evts, toolUseId) => {
      const parent = toolUseNode[toolUseId];
      if (!parent) return;
      parent.children.push(...this.buildSubagentNodes(evts));
    });
  }

  // Collapse streaming chains (same requestId = one API call) and build tokens.
  private buildSubagentNodes(events: RawEvent[]): Node[] {
    const byRequest = new Map<string, RawEvent[]>();
    for (const evt of events) {
      const reqId = evt.data?.message?.requestId || evt.uuid || "";
      getOrInit(byRequest, reqId).push(evt);
    }

    return Array.from(byRequest.values())
      .sort((a, b) => {
        const tsA = a[0].timestamp ?? "";
        const tsB = b[0].timestamp ?? "";
        return tsA < tsB ? -1 : tsA > tsB ? 1 : 0;
      })
      .map((group) => this.subagentToken(group))
      .map((t) => ({ token: t, children: [] }));
  }

  private subagentToken(group: RawEvent[]): Token {
    const representative = group[0];
    const msgData = representative.data?.message;
    const inner = msgData?.message ?? {};
    const usage = inner.usage ?? {};

    // Combine tool_uses across streaming events in this API call (parallel tools)
    const seenIds = new Map<string, Record<string, unknown>>();
    for (const evt of group) {
      const contentArr = evt.data?.message?.message?.content;
      if (!Array.isArray(contentArr)) continue;
      for (const b of contentArr) {
        if (
          typeof b === "object" &&
          b !== null &&
          (b as Record<string, unknown>).type === "tool_use"
        ) {
          const tu = b as Record<string, unknown>;
          const id = tu.id as string;
          if (id && !seenIds.has(id)) {
            seenIds.set(id, tu);
          }
        }
      }
    }

    const combinedToolUses = Array.from(seenIds.values());
    const rawContent =
      combinedToolUses.length > 0
        ? combinedToolUses
        : Array.isArray(inner.content)
          ? inner.content
          : inner.content == null
            ? []
            : [inner.content];

    const content = rawContent as Token["content"];

    return {
      uuid: msgData?.uuid || representative.uuid || null,
      parentUuid: null,
      requestId: msgData?.requestId || null,
      type: "assistant",
      role: "assistant",
      model: inner.model ?? null,
      isSidechain: true,
      agentId: representative.data?.agentId ?? null,
      content,
      inputTokens: usage.input_tokens ?? 0,
      outputTokens: usage.output_tokens ?? 0,
      cacheReadTokens: usage.cache_read_input_tokens ?? 0,
      cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
      marginalInputTokens: 0,
      timestamp: representative.timestamp ?? null,
      isCompaction: false,
    };
  }

  // Wire task-notification user turns back to the Agent call that spawned them.
  // Each <task-notification> contains a <tool-use-id> that matches an Agent
  // tool call in the main thread. We detach the notification from its current
  // tree position, mark it isSidechain, and attach it under the Agent call node.
  private attachTaskNotifications(tree: Node[]): void {
    const all = this.flattenNodes(tree);

    const agentNodeByToolUse: Record<string, Node> = {};
    all.forEach((node) => {
      toolUses(node.token).forEach((tu) => {
        if (tu.name === "Agent" && tu.id) {
          agentNodeByToolUse[tu.id] = node;
        }
      });
    });

    if (Object.keys(agentNodeByToolUse).length === 0) return;

    all
      .filter((n) => isTaskNotification(n.token))
      .forEach((node) => {
        const text = humanText(node.token);
        const match = text.match(/<tool-use-id>\s*([\s\S]*?)\s*<\/tool-use-id>/);
        if (!match) return;
        const toolUseId = match[1];
        const agentNode = agentNodeByToolUse[toolUseId];
        if (!agentNode) return;
        if (!this.removeNode(tree, node)) return;

        node.token = withToken(node.token, { isSidechain: true });
        agentNode.children.push(node);
      });
  }

  private removeNode(nodes: Node[], target: Node): boolean {
    const i = nodes.indexOf(target);
    if (i >= 0) {
      nodes.splice(i, 1);
      return true;
    }
    return nodes.some((node) => this.removeNode(node.children, target));
  }

  private flattenNodes(nodes: Node[]): Node[] {
    return nodes.flatMap((n) => [n, ...this.flattenNodes(n.children)]);
  }

  private readRawEvents(): RawEvent[] {
    const content = this.readFile();
    try {
      if (content.trimStart().startsWith("[")) {
        // Captured format: JSON array of {"event": {...}} wrappers produced by `record`
        const parsed = JSON.parse(content) as RawEvent[];
        return parsed.map((e) => (e.event ?? e) as RawEvent);
      } else {
        // Raw JSONL: newline-delimited events from ~/.claude/projects/*/...jsonl
        return content
          .split("\n")
          .filter((line) => line.trim().length > 0)
          .map((line) => {
            try {
              return JSON.parse(line) as RawEvent;
            } catch {
              return null;
            }
          })
          .filter((e): e is RawEvent => e !== null);
      }
    } catch (e) {
      throw new ParseError(
        `Failed to parse ${this.filePath}: ${e instanceof Error ? e.message : String(e)}`,
      );
    }
  }

  private readFile(): string {
    try {
      return readFileSync(this.filePath, "utf-8");
    } catch (e) {
      throw new ParseError(`Failed to read file: ${e instanceof Error ? e.message : String(e)}`);
    }
  }
}
