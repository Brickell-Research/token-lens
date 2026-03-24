import { describe, expect, it } from "bun:test";
import type { Node, Token } from "../types";
import { annotate, layout } from "./layout";

function makeToken(overrides: Partial<Token> = {}): Token {
  return {
    uuid: "test-uuid",
    parentUuid: null,
    requestId: null,
    type: "assistant",
    role: "assistant",
    model: null,
    isSidechain: false,
    agentId: null,
    content: [],
    inputTokens: 0,
    outputTokens: 0,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    marginalInputTokens: 0,
    timestamp: null,
    isCompaction: false,
    ...overrides,
  };
}

function node(opts: {
  inputTokens?: number;
  outputTokens?: number;
  role?: string;
  children?: Node[];
}): Node {
  return {
    token: makeToken({
      role: opts.role ?? "assistant",
      inputTokens: opts.inputTokens ?? 0,
      outputTokens: opts.outputTokens ?? 0,
      marginalInputTokens: opts.inputTokens ?? 0,
    }),
    children: opts.children ?? [],
  };
}

function annotateAndLayout(tree: Node[]): void {
  annotate(tree);
  layout(tree);
}

describe("layout", () => {
  it("single root spans the full canvas width", () => {
    const tree = [node({ inputTokens: 500 })];
    annotateAndLayout(tree);
    expect(tree[0].x).toBe(0);
    expect(tree[0].w).toBe(1200);
  });

  it("two equal roots each get half the canvas", () => {
    const tree = [node({ inputTokens: 100 }), node({ inputTokens: 100 })];
    annotateAndLayout(tree);
    expect(tree[0].x).toBe(0);
    expect(tree[0].w).toBe(600);
    expect(tree[1].x).toBe(600);
    expect(tree[1].w).toBe(600);
  });

  it("child starts at parent x", () => {
    const child = node({ inputTokens: 100 });
    const tree = [node({ inputTokens: 200, children: [child] })];
    annotateAndLayout(tree);
    expect(child.x).toBe(tree[0].x);
  });

  it("sets y based on depth (bottom-up: roots at bottom, children above)", () => {
    const child = node({ inputTokens: 100 });
    const tree = [node({ inputTokens: 200, children: [child] })];
    annotateAndLayout(tree);
    // max_depth=1: root (depth=0) is at y=ROW_HEIGHT, child (depth=1) at y=0
    expect(tree[0].y).toBe(32); // ROW_HEIGHT
    expect(child.y).toBe(0);
  });

  describe("cost layout", () => {
    it("sets costX and costW on nodes", () => {
      const tree = [node({ inputTokens: 500, outputTokens: 100 })];
      annotateAndLayout(tree);
      expect(tree[0].costX).toBe(0);
      expect(tree[0].costW).toBe(1200);
    });

    it("allocates costW proportional to subtreeCost", () => {
      // With fallback pricing, output tokens cost 5x input tokens.
      // node A: 0 input, 100 output -> cost = 100 * 15 / 1M = 0.0015
      // node B: 0 input, 300 output -> cost = 300 * 15 / 1M = 0.0045
      // ratio: A gets 1200 * 0.0015/0.006 = 300, B gets 900
      const a = node({ outputTokens: 100 });
      const b = node({ outputTokens: 300 });
      const tree = [a, b];
      annotateAndLayout(tree);
      expect(a.costW).toBe(300);
      expect(b.costW).toBe(900);
    });

    it("child costX starts at parent costX", () => {
      const child = node({ outputTokens: 50 });
      const parent = node({ outputTokens: 200, children: [child] });
      annotateAndLayout([parent]);
      expect(child.costX).toBe(parent.costX);
    });
  });
});
