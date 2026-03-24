import { mkdirSync, writeFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { homedir } from "node:os";
import type { RawEvent } from "../types";
import { startJsonlSource } from "../sources/jsonl";

export interface RecordOptions {
  durationInSeconds: number;
  projectDir?: string;
  output?: string;
}

export class RecordCommand {
  private opts: RecordOptions;

  constructor(opts: RecordOptions) {
    this.opts = opts;
  }

  async run(): Promise<void> {
    const { durationInSeconds } = this.opts;
    const outputPath = this.savePath();

    mkdirSync(dirname(outputPath), { recursive: true });

    const events: RawEvent[] = [];

    const stop = startJsonlSource({
      projectDir: this.opts.projectDir,
      onEvent: (e) => events.push(e),
    });

    process.stderr.write(`Recording for ${durationInSeconds}s... (Ctrl+C to stop early)\n`);
    process.stderr.write(`Output: ${outputPath}\n`);

    let finished = false;

    const finish = () => {
      if (finished) return;
      finished = true;
      stop();
      process.stderr.write(`\nCaptured ${events.length} events\n`);
      writeFileSync(
        outputPath,
        JSON.stringify(
          events.map((e) => ({ event: e })),
          null,
          2
        )
      );
      process.stderr.write(`Saved to ${outputPath}\n`);
      process.exit(0);
    };

    setTimeout(finish, durationInSeconds * 1000);
    process.on("SIGINT", finish);
    process.on("SIGTERM", finish);

    await new Promise(() => {});
  }

  private savePath(): string {
    if (this.opts.output) {
      return this.opts.output;
    }
    return join(homedir(), ".token-lens", "sessions", `${Date.now()}.json`);
  }
}
