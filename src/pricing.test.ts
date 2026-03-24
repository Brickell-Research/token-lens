import { describe, expect, it } from "bun:test";
import { getRatesForModel } from "./pricing";

describe("getRatesForModel", () => {
  it("returns opus-4-6 rates for claude-opus-4-6 models", () => {
    const rates = getRatesForModel("claude-opus-4-6");
    expect(rates.input).toBe(5.0);
    expect(rates.output).toBe(25.0);
  });

  it("returns opus-4-0 rates for claude-opus-4-20250514 models", () => {
    const rates = getRatesForModel("claude-opus-4-20250514");
    expect(rates.input).toBe(15.0);
    expect(rates.output).toBe(75.0);
  });

  it("returns sonnet rates for claude-sonnet-4 models", () => {
    const rates = getRatesForModel("claude-sonnet-4-6");
    expect(rates.input).toBe(3.0);
    expect(rates.cacheRead).toBe(0.3);
  });

  it("returns haiku-4-5 rates for claude-haiku-4-5 models", () => {
    const rates = getRatesForModel("claude-haiku-4-5-20251001");
    expect(rates.input).toBe(1.0);
    expect(rates.output).toBe(5.0);
  });

  it("returns fallback rates for unknown models", () => {
    const rates = getRatesForModel("claude-unknown-model");
    expect(rates).toEqual({ input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 });
  });

  it("returns fallback rates when model is null", () => {
    const rates = getRatesForModel(null);
    expect(rates).toEqual({ input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 });
  });

  it("returns fallback rates when model is undefined", () => {
    const rates = getRatesForModel(undefined);
    expect(rates).toEqual({ input: 3.0, cacheRead: 0.3, cacheCreation: 3.75, output: 15.0 });
  });
});
