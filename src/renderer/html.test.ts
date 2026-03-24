import { describe, expect, it } from "bun:test";
import type { Node, Token } from "../types";
import { Html } from "./html";
import { annotate, layout } from "./layout";

function makeToken(overrides: Partial<Token> = {}): Token {
  return {
    uuid: "test-uuid",
    parentUuid: null,
    requestId: null,
    type: overrides.role ?? "assistant",
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
  toolName?: string;
  text?: string;
  children?: Node[];
}): Node {
  let content: Token["content"];
  if (opts.toolName) {
    content = [{ type: "tool_use", id: "t1", name: opts.toolName }];
  } else if (opts.text) {
    content = [{ type: "text", text: opts.text }];
  } else {
    content = [];
  }

  return {
    token: makeToken({
      role: opts.role ?? "assistant",
      inputTokens: opts.inputTokens ?? 0,
      outputTokens: opts.outputTokens ?? 0,
      marginalInputTokens: opts.inputTokens ?? 0,
      content,
    }),
    children: opts.children ?? [],
  };
}

function renderTree(tree: Node[]): string {
  annotate(tree);
  layout(tree);
  return new Html().render(tree);
}

describe("Html", () => {
  it("produces a valid HTML document", () => {
    const html = renderTree([node({ inputTokens: 500, outputTokens: 100 })]);
    expect(html).toContain("<!DOCTYPE html>");
    expect(html).toContain("</html>");
  });

  it("contains a bar div for each node", () => {
    const tree = [node({ inputTokens: 100, children: [node({ inputTokens: 50 })] })];
    const result = renderTree(tree);
    const matches = result.match(/class="bar bar-c-/g);
    expect(matches?.length).toBe(2);
  });

  it("uses assistant color class for assistant nodes", () => {
    const html = renderTree([node({ inputTokens: 500, outputTokens: 100 })]);
    expect(html).toContain("bar-c-assistant");
  });

  it("uses tool color class for assistant nodes with tool uses", () => {
    const result = renderTree([node({ inputTokens: 500, toolName: "Bash" })]);
    expect(result).toContain("bar-c-tool");
  });

  it("labels human prompt nodes with their text", () => {
    const result = renderTree([
      node({ role: "user", text: "How does this work?", inputTokens: 500 }),
    ]);
    expect(result).toContain("How does this work?");
  });

  it("hides label for narrow bars", () => {
    const wide = node({ inputTokens: 975 });
    const narrow = node({ inputTokens: 25 });
    const result = renderTree([wide, narrow]);
    expect(result).toContain("display:none");
  });

  it("escapes HTML special chars in labels and tooltips", () => {
    const result = renderTree([
      node({
        role: "user",
        text: "<script>alert('xss')</script>",
        inputTokens: 500,
      }),
    ]);
    expect(result).not.toContain("<script>alert");
    expect(result).toContain("&lt;script&gt;");
  });
});
