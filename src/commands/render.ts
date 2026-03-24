import { existsSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parse } from "../parser";
import { Html } from "../renderer/html";
import { annotate, layout } from "../renderer/layout";
import { reshape } from "../renderer/reshaper";
import { activeOrLatestJsonl } from "../session";

export interface RenderOptions {
  filePath?: string;
  output: string;
}

export async function render(opts: RenderOptions): Promise<void> {
  let filePath = opts.filePath;
  if (!filePath) {
    const sessionsDir = join(homedir(), ".token-lens", "sessions");
    if (existsSync(sessionsDir)) {
      const files = readdirSync(sessionsDir)
        .filter((f) => f.endsWith(".json"))
        .map((f) => join(sessionsDir, f))
        .filter((p) => statSync(p).isFile())
        .sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
      filePath = files[0];
    }
    if (!filePath) {
      process.stderr.write(
        "No saved captures found — reading active Claude Code session directly\n",
      );
      filePath = activeOrLatestJsonl();
    }
  }
  process.stderr.write(`Rendering ${filePath}\n`);
  const tree = parse(filePath);
  const reshapedTree = reshape(tree);
  if (reshapedTree.length === 0) {
    process.stderr.write(
      `Warning: no conversation turns found in ${filePath} — output will be empty.\n`,
    );
  }
  reshapedTree.sort((a, b) => (a.token.timestamp ?? "").localeCompare(b.token.timestamp ?? ""));
  annotate(reshapedTree);
  const canvasWidth = layout(reshapedTree);
  const html = new Html(canvasWidth).render(reshapedTree);
  writeFileSync(opts.output, html);
  console.log(`Wrote ${opts.output}`);
}
