import { describe, expect, it } from "bun:test";
import { costUsd } from "../token";
import type { Node, Token } from "../types";
import { annotate } from "./layout";

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

describe("annotate", () => {
  it("sets depth 0 on root nodes", () => {
    const tree = [node({ inputTokens: 100 })];
    annotate(tree);
    expect(tree[0].depth).toBe(0);
  });

  it("sets depth 1 on children", () => {
    const child = node({ inputTokens: 50 });
    const tree = [node({ inputTokens: 100, children: [child] })];
    annotate(tree);
    expect(child.depth).toBe(1);
  });

  it("subtreeTokens for a leaf = own displayWidth", () => {
    // displayWidth = marginalInputTokens + cacheCreationTokens + outputTokens
    // With marginalInputTokens=100, outputTokens=50, cacheCreation=0 -> displayWidth=150
    const tree = [node({ inputTokens: 100, outputTokens: 50 })];
    annotate(tree);
    expect(tree[0].subtreeTokens).toBe(150);
  });

  it("subtreeTokens for parent = own tokens + child subtreeTokens", () => {
    const child = node({ inputTokens: 200 });
    const tree = [node({ inputTokens: 100, children: [child] })];
    annotate(tree);
    expect(tree[0].subtreeTokens).toBe(300);
  });

  it("gives 0-token nodes a minimum subtreeTokens of 1", () => {
    const tree = [node({ role: "user" })];
    annotate(tree);
    expect(tree[0].subtreeTokens).toBe(1);
  });

  describe("subtreeCost", () => {
    it("sets subtreeCost on a leaf node", () => {
      // fallback sonnet-4 rates: input $3/MTok, output $15/MTok
      // cost = (100 * 3.0 + 50 * 15.0) / 1_000_000 = 0.00105
      const tree = [node({ inputTokens: 100, outputTokens: 50 })];
      annotate(tree);
      expect(Math.abs((tree[0].subtreeCost ?? 0) - 0.00105)).toBeLessThan(0.0000001);
    });

    it("rolls up subtreeCost through children", () => {
      const child = node({ inputTokens: 100, outputTokens: 50 });
      const parent = node({
        inputTokens: 200,
        outputTokens: 80,
        children: [child],
      });
      annotate([parent]);
      const childCost = child.subtreeCost ?? 0;
      const parentOwnCost = costUsd(parent.token);
      expect(Math.abs((parent.subtreeCost ?? 0) - (parentOwnCost + childCost))).toBeLessThan(
        0.0000001,
      );
    });

    it("sets subtreeCost to 0 for zero-token user nodes", () => {
      const tree = [node({ role: "user" })];
      annotate(tree);
      expect(tree[0].subtreeCost).toBe(0);
    });
  });
});
