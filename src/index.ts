#!/usr/bin/env bun
import { Command } from "commander";
import { RecordCommand } from "./commands/record";
import { Render } from "./commands/render";

const program = new Command();
program
  .name("token-lens")
  .description("Flame graphs for Claude Code token usage")
  .version("0.6.0");

program
  .command("record")
  .description("Tail the active session and auto-save a capture file")
  .option("--duration-in-seconds <n>", "Seconds to record", "30")
  .option(
    "--project-dir <path>",
    "Working directory of the Claude Code session to record",
  )
  .option("--output <path>", "Save path for the capture")
  .action(async (opts) => {
    await new RecordCommand({
      durationInSeconds: parseInt(opts.durationInSeconds, 10),
      projectDir: opts.projectDir,
      output: opts.output,
    }).run();
  });

program
  .command("render")
  .description("Render a captured session as a flame graph")
  .option("--file-path <path>", "Path to the captured JSON file")
  .option("--output <path>", "Output HTML path", "flame.html")
  .action(async (opts) => {
    await new Render({
      filePath: opts.filePath,
      output: opts.output,
    }).run();
  });

program.parseAsync();
