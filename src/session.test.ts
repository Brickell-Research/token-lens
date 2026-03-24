import { describe, it, expect } from "bun:test";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { encodedCwd } from "./session";

describe("encodedCwd", () => {
  it("replaces non-alphanumeric characters with hyphens", () => {
    expect(encodedCwd("/Users/me/my-project")).toBe("-Users-me-my-project");
  });

  it("leaves alphanumeric characters unchanged", () => {
    expect(encodedCwd("abc123")).toBe("abc123");
  });

  it("handles paths with dots and spaces", () => {
    expect(encodedCwd("/home/user/my.project name")).toBe(
      "-home-user-my-project-name"
    );
  });
});
