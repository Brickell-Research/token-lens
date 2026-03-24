import { describe, it, expect } from "bun:test";
import { Reshaper } from "./reshaper";
import { isHumanPrompt, humanText } from "../token";
import type { Node, Token } from "../types";

function makeToken(opts: {
  role: string;
  input?: number;
  output?: number;
  cacheCreation?: number;
  isSidechain?: boolean;
  text?: string;
  toolResult?: boolean;
}): Token {
  let content: Token["content"];
  if (opts.text) {
    content = [{ type: "text", text: opts.text }];
  } else if (opts.toolResult) {
    content = [{ type: "tool_result", id: "t1" }];
  } else {
    content = [];
  }

  return {
    uuid: `uuid-${Math.floor(Math.random() * 10000)}`,
    parentUuid: null,
    requestId: null,
    type: opts.role,
    role: opts.role,
    model: null,
    isSidechain: opts.isSidechain ?? false,
    agentId: null,
    content,
    inputTokens: opts.input ?? 0,
    outputTokens: opts.output ?? 0,
    cacheReadTokens: 0,
    cacheCreationTokens: opts.cacheCreation ?? 0,
    marginalInputTokens: 0,
    timestamp: null,
    isCompaction: false,
  };
}

function mkNode(tok: Token, children: Node[] = []): Node {
  return { token: tok, children };
}

describe("Reshaper", () => {
  describe("human prompt re-rooting", () => {
    it("makes human prompt a root with assistant turns as siblings", () => {
      const a2 = mkNode(makeToken({ role: "assistant", input: 200, output: 50 }));
      const toolResult = mkNode(
        makeToken({ role: "user", toolResult: true }),
        [a2]
      );
      const a1 = mkNode(
        makeToken({ role: "assistant", input: 100, output: 30 }),
        [toolResult]
      );
      const prompt = mkNode(
        makeToken({ role: "user", text: "do something" }),
        [a1]
      );

      const reshaper = new Reshaper();
      const result = reshaper.reshape([prompt]);

      expect(result.length).toBe(1);
      expect(isHumanPrompt(result[0].token)).toBe(true);
      expect(result[0].children.length).toBe(2);
      expect(result[0].children.map((c) => c.token.role)).toEqual([
        "assistant",
        "assistant",
      ]);
    });

    it("computes marginalInputTokens as delta from previous turn", () => {
      const a2 = mkNode(makeToken({ role: "assistant", input: 300, output: 50 }));
      const toolResult = mkNode(
        makeToken({ role: "user", toolResult: true }),
        [a2]
      );
      const a1 = mkNode(
        makeToken({ role: "assistant", input: 100, output: 30 }),
        [toolResult]
      );
      const prompt = mkNode(makeToken({ role: "user", text: "go" }), [a1]);

      const reshaper = new Reshaper();
      const result = reshaper.reshape([prompt]);
      const siblings = result[0].children;

      expect(siblings[0].token.marginalInputTokens).toBe(100); // 100 - 0
      expect(siblings[1].token.marginalInputTokens).toBe(200); // 300 - 100
    });

    it("hoists nested human prompts to separate top-level roots", () => {
      const a2 = mkNode(makeToken({ role: "assistant", input: 200 }));
      const p2 = mkNode(makeToken({ role: "user", text: "follow-up" }), [a2]);
      const a1 = mkNode(makeToken({ role: "assistant", input: 100 }), [p2]);
      const p1 = mkNode(makeToken({ role: "user", text: "initial" }), [a1]);

      const reshaper = new Reshaper();
      const result = reshaper.reshape([p1]);

      expect(result.length).toBe(2);
      expect(humanText(result[0].token)).toBe("initial");
      expect(result[0].children.map((c) => c.token.role)).toEqual([
        "assistant",
      ]);
      expect(humanText(result[1].token)).toBe("follow-up");
      expect(result[1].children.map((c) => c.token.role)).toEqual([
        "assistant",
      ]);
    });

    it("preserves multiple human prompt roots as separate groups", () => {
      const a1 = mkNode(makeToken({ role: "assistant", input: 100 }));
      const a2 = mkNode(makeToken({ role: "assistant", input: 200 }));
      const p1 = mkNode(makeToken({ role: "user", text: "prompt one" }), [a1]);
      const p2 = mkNode(makeToken({ role: "user", text: "prompt two" }), [a2]);

      const reshaper = new Reshaper();
      const result = reshaper.reshape([p1, p2]);

      expect(result.length).toBe(2);
      expect(result.map((r) => humanText(r.token))).toEqual([
        "prompt one",
        "prompt two",
      ]);
    });
  });

  describe("streaming chain collapse", () => {
    it("collapses thinking->text->tool_use chains with identical input usage", () => {
      const toolUse = mkNode(
        makeToken({
          role: "assistant",
          input: 100,
          output: 500,
          cacheCreation: 200,
        })
      );
      const text = mkNode(
        makeToken({
          role: "assistant",
          input: 100,
          output: 8,
          cacheCreation: 200,
        }),
        [toolUse]
      );
      const thinking = mkNode(
        makeToken({
          role: "assistant",
          input: 100,
          output: 8,
          cacheCreation: 200,
        }),
        [text]
      );
      const prompt = mkNode(makeToken({ role: "user", text: "go" }), [
        thinking,
      ]);

      const reshaper = new Reshaper();
      const result = reshaper.reshape([prompt]);
      const siblings = result[0].children;

      expect(siblings.length).toBe(1);
      expect(siblings[0].token.outputTokens).toBe(500);
    });
  });

  describe("sidechain handling", () => {
    it("keeps sidechain nodes nested under the spawning assistant turn", () => {
      const sidechain = mkNode(
        makeToken({ role: "assistant", input: 50, isSidechain: true })
      );
      const a1 = mkNode(
        makeToken({ role: "assistant", input: 100 }),
        [sidechain]
      );
      const prompt = mkNode(makeToken({ role: "user", text: "go" }), [a1]);

      const reshaper = new Reshaper();
      const result = reshaper.reshape([prompt]);
      const assistant = result[0].children[0];

      expect(assistant.children.length).toBe(1);
      expect(assistant.children[0].token.isSidechain).toBe(true);
    });
  });
});
