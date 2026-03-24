import { getRatesForModel } from "./pricing";
import type { ContentBlock, RawEvent, Token } from "./types";

export function createToken(raw: RawEvent): Token {
  const msg = raw.message ?? {};
  const usage = msg.usage ?? {};

  const c = msg.content;
  const content = (Array.isArray(c) ? c : c == null ? [] : [c]) as (string | ContentBlock)[];

  return {
    uuid: raw.uuid ?? null,
    parentUuid: raw.parentUuid ?? null,
    requestId: raw.requestId ?? null,
    type: raw.type ?? "",
    role: msg.role ?? null,
    model: msg.model ?? null,
    isSidechain: raw.isSidechain ?? false,
    agentId: null,
    content,
    inputTokens: usage.input_tokens ?? 0,
    outputTokens: usage.output_tokens ?? 0,
    cacheReadTokens: usage.cache_read_input_tokens ?? 0,
    cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
    marginalInputTokens: 0,
    timestamp: raw.timestamp ?? null,
    isCompaction: false,
  };
}

export function withToken(token: Token, overrides: Partial<Token>): Token {
  return { ...token, ...overrides };
}

export function costUsd(token: Token): number {
  const p = getRatesForModel(token.model);
  return (
    (token.marginalInputTokens * p.input +
      token.cacheReadTokens * p.cacheRead +
      token.cacheCreationTokens * p.cacheCreation +
      token.outputTokens * p.output) /
    1_000_000
  );
}

export function totalTokens(token: Token): number {
  return token.inputTokens + token.outputTokens + token.cacheReadTokens + token.cacheCreationTokens;
}

export function displayWidth(token: Token): number {
  return token.marginalInputTokens + token.cacheCreationTokens + token.outputTokens;
}

export function isAssistant(token: Token): boolean {
  return token.role === "assistant";
}

export function humanText(token: Token): string {
  const strBlock = token.content.find((b): b is string => typeof b === "string");
  if (strBlock !== undefined) return strBlock;
  const textBlock = token.content.find(
    (b): b is ContentBlock => typeof b === "object" && b !== null && b.type === "text",
  );
  return textBlock?.text ?? "";
}

export function toolUses(token: Token): ContentBlock[] {
  return token.content.filter(
    (b): b is ContentBlock => typeof b === "object" && b !== null && b.type === "tool_use",
  );
}

export function toolResults(token: Token): ContentBlock[] {
  return token.content.filter(
    (b): b is ContentBlock => typeof b === "object" && b !== null && b.type === "tool_result",
  );
}

export function isHumanPrompt(token: Token): boolean {
  if (token.role !== "user") return false;
  if (toolResults(token).length > 0) return false;
  return token.content.some(
    (b) => typeof b === "string" || (typeof b === "object" && b !== null && b.type === "text"),
  );
}

export function isTaskNotification(token: Token): boolean {
  return isHumanPrompt(token) && humanText(token).startsWith("<task-notification>");
}

export function taskNotificationSummary(token: Token): string | null {
  const match = humanText(token).match(/<summary>([\s\S]*?)<\/summary>/);
  return match ? match[1].trim() : null;
}
