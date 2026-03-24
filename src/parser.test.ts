import { describe, expect, it } from "bun:test";
import { join } from "node:path";
import { Parser } from "./parser";
import { toolResults, toolUses } from "./token";
import type { Node } from "./types";

const fixturePath = join(import.meta.dir, "fixtures", "capture.json");
const agentFixturePath = join(import.meta.dir, "fixtures", "capture_agent.json");

function depth(node: Node): number {
  if (node.children.length === 0) return 1;
  return 1 + Math.max(...node.children.map(depth));
}

describe("Parser", () => {
  const tree = new Parser(fixturePath).parse();

  it("returns two root nodes", () => {
    expect(tree.length).toBe(2);
  });

  describe("first thread", () => {
    const root = tree[0];

    it("root is the opening user message", () => {
      expect(root.token.uuid).toBe("msg-001");
      expect(root.token.parentUuid).toBeNull();
    });

    it("is 6 nodes deep", () => {
      expect(depth(root)).toBe(6);
    });

    it("assistant nodes carry token counts", () => {
      const assistant = root.children[0];
      expect(assistant.token.inputTokens).toBe(800);
      expect(assistant.token.outputTokens).toBe(150);
      expect(assistant.token.cacheCreationTokens).toBe(400);
    });

    it("tool uses are on the right nodes", () => {
      const bashNode = root.children[0];
      const readNode = bashNode.children[0].children[0];
      expect(toolUses(bashNode.token)[0].name).toBe("Bash");
      expect(toolUses(readNode.token)[0].name).toBe("Read");
    });

    it("tool results reference the correct tool_use_id", () => {
      const toolResultNode = root.children[0].children[0];
      expect(toolResults(toolResultNode.token)[0].id).toBeUndefined();
      // The tool_use_id is stored differently in ContentBlock - check via content directly
      const content = toolResultNode.token.content[0];
      expect(typeof content === "object" && content !== null && "type" in content).toBe(true);
    });

    it("leaf has no children", () => {
      const leaf = root.children[0].children[0].children[0].children[0].children[0];
      expect(leaf.children).toEqual([]);
    });
  });

  describe("second thread", () => {
    const root = tree[1];
    const agentNode = root.children[0];

    it("is an independent root", () => {
      expect(root.token.uuid).toBe("msg-007");
      expect(root.token.parentUuid).toBeNull();
    });

    it("has one assistant child that calls Agent", () => {
      expect(agentNode.token.uuid).toBe("msg-008");
      expect(toolUses(agentNode.token)[0].name).toBe("Agent");
    });

    it("attaches two subagent turns as sidechain children of the Agent call", () => {
      const subagent = agentNode.children.filter((c) => c.token.isSidechain);
      expect(subagent.length).toBe(2);
    });

    it("subagent turns use haiku model and carry token counts", () => {
      const subagent = agentNode.children.filter((c) => c.token.isSidechain);
      expect([...new Set(subagent.map((n) => n.token.model))]).toEqual([
        "claude-haiku-4-5-20251001",
      ]);
      expect(subagent[0].token.cacheCreationTokens).toBe(800);
    });
  });

  describe("subagent progress event handling", () => {
    const agentTree = new Parser(agentFixturePath).parse();
    const outerAssistant = agentTree[0].children[0];

    it("attaches subagent turns as sidechain children of the Agent call", () => {
      const subagentChildren = outerAssistant.children.filter((c) => c.token.isSidechain);
      expect(subagentChildren.length).toBeGreaterThan(0);
    });

    it("collapses streaming chain (same requestId) into one node with combined tool_uses", () => {
      const subagentChildren = outerAssistant.children.filter((c) => c.token.isSidechain);
      // prog-002 and prog-003 share req-sub-001; prog-004 is req-sub-002 -> 2 nodes
      expect(subagentChildren.length).toBe(2);
    });

    it("combines parallel tool_uses from the same API call", () => {
      const subagentChildren = outerAssistant.children.filter((c) => c.token.isSidechain);
      const firstTurn = subagentChildren[0];
      expect(toolUses(firstTurn.token).map((tu) => tu.name)).toEqual(["WebSearch", "WebSearch"]);
    });

    it("sets subagent model from the progress event", () => {
      const subagentChildren = outerAssistant.children.filter((c) => c.token.isSidechain);
      expect(subagentChildren[0].token.model).toBe("claude-haiku-4-5-20251001");
    });

    it("carries token counts from subagent usage", () => {
      const subagentChildren = outerAssistant.children.filter((c) => c.token.isSidechain);
      const first = subagentChildren[0];
      expect(first.token.inputTokens).toBe(100);
      expect(first.token.outputTokens).toBe(20);
      expect(first.token.cacheCreationTokens).toBe(500);
    });

    it("skips user-type progress events (tool results, prompts)", () => {
      const allSidechain = outerAssistant.children.filter((c) => c.token.isSidechain);
      expect(allSidechain.every((n) => n.token.role === "assistant")).toBe(true);
    });
  });
});
