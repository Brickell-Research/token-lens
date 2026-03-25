#!/usr/bin/env bun
import { Command } from "commander";
import { record } from "./commands/record";
import { render } from "./commands/render";
import { watch } from "./commands/watch";

const program = new Command();
program
  .name("token-lens")
  .description("Flame graphs for Claude Code token usage")
  .version("0.11.0");

program
  .command("record")
  .description("Tail the active session and auto-save a capture file")
  .option("--duration-in-seconds <n>", "Stop after N seconds (default: run until Ctrl+C)")
  .option("--project-dir <path>", "Working directory of the Claude Code session to record")
  .option("--output <path>", "Save path for the capture")
  .action(async (opts) => {
    await record({
      durationInSeconds: opts.durationInSeconds
        ? (() => {
            const n = parseInt(opts.durationInSeconds, 10);
            if (Number.isNaN(n)) {
              process.stderr.write("Error: --duration-in-seconds must be a number\n");
              process.exit(1);
            }
            return n;
          })()
        : undefined,
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

program
  .command("watch")
  .description("Watch a session and serve a live-updating flame graph")
  .option("--live", "Auto-select the active Claude Code session (skips picker)")
  .option("--project-dir <path>", "Working directory of the Claude Code session (implies --live)")
  .option("--file-path <path>", "Session file (JSONL or JSON)")
  .option("--output <path>", "Output HTML path (default: flame.html)")
  .option("--interval <ms>", "Browser reload interval in ms (default: 2000)")
  .action(async (opts) => {
    await watch({
      live: opts.live,
      projectDir: opts.projectDir,
      filePath: opts.filePath,
      output: opts.output,
      intervalMs: opts.interval ? parseInt(opts.interval, 10) : undefined,
    });
  });

program.parseAsync();
