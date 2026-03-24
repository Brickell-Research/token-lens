import type { Rate } from "./types";

// Prices in USD per million tokens. Source: platform.claude.com/docs/en/about-claude/pricing
// Last verified: 2026-03-23
//
// cacheCreation = 5-minute cache write (1.25x input). The API reports this as
// cache_creation_input_tokens in the usage object.
// cacheRead     = cache hit (0.1x input).
//
// Entries are matched via String#startsWith in order — put more specific prefixes first.
export const PRICING_TABLE: ReadonlyArray<readonly [string, Rate]> = [
  ["claude-opus-4-6", { input: 5.0, cacheRead: 0.5, cacheCreation: 6.25, output: 25.0 }],
  ["claude-opus-4-5", { input: 5.0, cacheRead: 0.5, cacheCreation: 6.25, output: 25.0 }],
  ["claude-opus-4", { input: 15.0, cacheRead: 1.5, cacheCreation: 18.75, output: 75.0 }],
  ["claude-sonnet-4", { input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 }],
  ["claude-haiku-4-5", { input: 1.0, cacheRead: 0.1, cacheCreation: 1.25, output: 5.0 }],
  ["claude-haiku-4", { input: 1.0, cacheRead: 0.1, cacheCreation: 1.25, output: 5.0 }],
  ["claude-sonnet-3", { input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 }],
  ["claude-haiku-3-5", { input: 0.8, cacheRead: 0.08, cacheCreation: 1.0, output: 4.0 }],
  ["claude-3-opus", { input: 15.0, cacheRead: 1.5, cacheCreation: 18.75, output: 75.0 }],
  ["claude-3-5-sonnet", { input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 }],
  ["claude-3-sonnet", { input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 }],
  ["claude-3-5-haiku", { input: 0.8, cacheRead: 0.08, cacheCreation: 1.0, output: 4.0 }],
  ["claude-3-haiku", { input: 0.25, cacheRead: 0.03, cacheCreation: 0.3, output: 1.25 }],
];

// Fallback when model string is nil or unrecognised — use Sonnet 4 rates
const DEFAULT_RATE: Rate = { input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 };

export function getRatesForModel(model: string | null | undefined): Rate {
  return PRICING_TABLE.find(([prefix]) => model?.startsWith(prefix))?.[1] ?? DEFAULT_RATE;
}
