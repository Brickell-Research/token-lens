#!/usr/bin/env bun
import { Command } from "commander";
import { record } from "./commands/record";
import { render } from "./commands/render";

const program = new Command();
program
  .name("token-lens")
  .description("Flame graphs for Claude Code token usage")
  .version("0.9.0");

program
  .command("record")
  .description("Tail the active session and auto-save a capture file")
  .option("--duration-in-seconds <n>", "Stop after N seconds (default: run until Ctrl+C)")
  .option(
    "--project-dir <path>",
    "Working directory of the Claude Code session to record",
  )
  .option("--output <path>", "Save path for the capture")
  .action(async (opts) => {
    await record({
      durationInSeconds: opts.durationInSeconds ? parseInt(opts.durationInSeconds, 10) : undefined,
      projectDir: opts.projectDir,
      output: opts.output,
    });
  });

program
  .command("render")
  .description("Render a captured session as a flame graph")
  .option("--file-path <path>", "Path to the captured JSON file")
  .option("--output <path>", "Output HTML path", "flame.html")
  .action(async (opts) => {
    await render({
      filePath: opts.filePath,
      output: opts.output,
    });
  });

program.parseAsync();
