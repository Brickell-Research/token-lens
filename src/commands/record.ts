import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { activeJsonl, activeOrLatestJsonl, SESSIONS_DIR, tailFile } from "../session";
import type { RawEvent } from "../types";

export interface RecordOptions {
  durationInSeconds?: number;
  projectDir?: string;
  output?: string;
}

export async function record(opts: RecordOptions): Promise<void> {
  const outputPath = opts.output ?? join(SESSIONS_DIR, `${Date.now()}.json`);
  mkdirSync(SESSIONS_DIR, { recursive: true });
  mkdirSync(dirname(outputPath), { recursive: true });

  const events: RawEvent[] = [];
  const jsonlPath = opts.projectDir ? activeJsonl(opts.projectDir) : activeOrLatestJsonl();
  process.stderr.write(`Recording: ${jsonlPath}\n`);
  const stop = tailFile(jsonlPath, (e) => events.push(e));

  const durationMsg =
    opts.durationInSeconds !== undefined
      ? `Recording for ${opts.durationInSeconds}s — Ctrl+C to stop early\n`
      : `Recording — press Ctrl+C to stop and save\n`;
  process.stderr.write(durationMsg);
  process.stderr.write(`Output: ${outputPath}\n`);

  let finished = false;

  const ticker = setInterval(() => {
    if (!finished) process.stderr.write(`  ${events.length} events captured...\n`);
  }, 5000);

  const finish = () => {
    if (finished) return;
    finished = true;
    clearInterval(ticker);
    stop();
    process.stderr.write(`\nCaptured ${events.length} events\n`);
    writeFileSync(
      outputPath,
      JSON.stringify(
        events.map((e) => ({ event: e })),
        null,
        2,
      ),
    );
    process.stderr.write(`Saved to ${outputPath}\n`);
    process.exit(0);
  };

  if (opts.durationInSeconds !== undefined) {
    setTimeout(finish, opts.durationInSeconds * 1000);
  }
  process.on("SIGINT", finish);
  process.on("SIGTERM", finish);
  await new Promise(() => {});
}
