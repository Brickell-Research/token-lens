import { describe, expect, it } from "bun:test";
import {
  costUsd,
  createToken,
  displayWidth,
  humanText,
  isAssistant,
  isHumanPrompt,
  toolUses,
  totalTokens,
  withToken,
} from "./token";
import type { RawEvent, Token } from "./types";

function makeRaw(overrides: Partial<RawEvent> = {}): RawEvent {
  return {
    uuid: "abc-123",
    parentUuid: "parent-456",
    type: "assistant",
    message: {
      role: "assistant",
      content: [{ type: "text", text: "hello" }],
      usage: {
        input_tokens: 100,
        output_tokens: 50,
        cache_read_input_tokens: 200,
        cache_creation_input_tokens: 10,
      },
    },
    ...overrides,
  };
}

function makeUserRaw(content: unknown[]): RawEvent {
  return makeRaw({ type: "user", message: { role: "user", content } });
}

function makeZeroCostToken(overrides: Partial<Token> = {}): Token {
  const base = createToken(makeRaw());
  return withToken(base, {
    marginalInputTokens: 0,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    outputTokens: 0,
    ...overrides,
  });
}

describe("createToken", () => {
  it("parses identifiers", () => {
    const token = createToken(makeRaw());
    expect(token.uuid).toBe("abc-123");
    expect(token.parentUuid).toBe("parent-456");
    expect(token.type).toBe("assistant");
    expect(token.role).toBe("assistant");
  });

  it("parses requestId", () => {
    const token = createToken(makeRaw({ requestId: "req_abc123" }));
    expect(token.requestId).toBe("req_abc123");
  });

  it("defaults requestId to null when absent", () => {
    const token = createToken(makeRaw());
    expect(token.requestId).toBeNull();
  });

  it("parses token counts", () => {
    const token = createToken(makeRaw());
    expect(token.inputTokens).toBe(100);
    expect(token.outputTokens).toBe(50);
    expect(token.cacheReadTokens).toBe(200);
    expect(token.cacheCreationTokens).toBe(10);
  });

  it("computes totalTokens", () => {
    const token = createToken(makeRaw());
    expect(totalTokens(token)).toBe(360);
  });

  it("identifies assistant messages", () => {
    const token = createToken(makeRaw());
    expect(isAssistant(token)).toBe(true);
  });

  it("extracts toolUses from content", () => {
    const raw = makeRaw();
    (raw.message?.content as unknown[]).push({
      type: "tool_use",
      id: "t1",
      name: "Bash",
    });
    const token = createToken(raw);
    expect(toolUses(token)).toEqual([{ type: "tool_use", id: "t1", name: "Bash" }]);
  });

  it("handles missing usage gracefully", () => {
    const raw = makeRaw();
    delete raw.message?.usage;
    const token = createToken(raw);
    expect(token.inputTokens).toBe(0);
    expect(totalTokens(token)).toBe(0);
  });

  it("defaults marginalInputTokens to 0", () => {
    const token = createToken(makeRaw());
    expect(token.marginalInputTokens).toBe(0);
  });

  it("defaults agentId to null", () => {
    const token = createToken(makeRaw());
    expect(token.agentId).toBeNull();
  });
});

describe("withToken", () => {
  it("stores agentId when set via withToken", () => {
    const token = createToken(makeRaw());
    const t = withToken(token, { agentId: "agent-123" });
    expect(t.agentId).toBe("agent-123");
  });

  it("computes displayWidth from marginal_input + cache_creation + output", () => {
    const token = createToken(makeRaw());
    const t = withToken(token, { marginalInputTokens: 50 });
    expect(displayWidth(t)).toBe(50 + 10 + 50); // marginal + cache_creation + output
  });
});

describe("costUsd", () => {
  it("computes cost using marginal input, cache reads, cache creation, and output", () => {
    // fallback sonnet-4 rates: input $3/MTok
    expect(
      Math.abs(costUsd(makeZeroCostToken({ marginalInputTokens: 1_000_000 })) - 3.0),
    ).toBeLessThan(0.000001);
  });

  it("uses model-specific pricing for opus-4-6", () => {
    expect(
      Math.abs(
        costUsd(makeZeroCostToken({ model: "claude-opus-4-6", marginalInputTokens: 1_000_000 })) -
          5.0,
      ),
    ).toBeLessThan(0.000001);
  });

  it("uses model-specific pricing for haiku-4-5", () => {
    expect(
      Math.abs(
        costUsd(
          makeZeroCostToken({ model: "claude-haiku-4-5-20251001", marginalInputTokens: 1_000_000 }),
        ) - 1.0,
      ),
    ).toBeLessThan(0.000001);
  });

  it("returns 0 for a token with all zero counts", () => {
    expect(costUsd(makeZeroCostToken())).toBe(0);
  });
});

describe("isHumanPrompt", () => {
  it("is true for user text messages", () => {
    const token = createToken(makeUserRaw([{ type: "text", text: "hello" }]));
    expect(isHumanPrompt(token)).toBe(true);
  });

  it("is false for user tool_result messages", () => {
    const token = createToken(makeUserRaw([{ type: "tool_result", text: "" }]));
    expect(isHumanPrompt(token)).toBe(false);
  });

  it("is false for assistant messages", () => {
    const token = createToken(makeRaw());
    expect(isHumanPrompt(token)).toBe(false);
  });
});

describe("humanText", () => {
  it("returns the text content of a human message", () => {
    const token = createToken(makeUserRaw([{ type: "text", text: "How does this work?" }]));
    expect(humanText(token)).toBe("How does this work?");
  });
});
