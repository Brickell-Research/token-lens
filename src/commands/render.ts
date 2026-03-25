import { writeFileSync } from "node:fs";
import { parse } from "../parser";
import { Html } from "../renderer/html";
import { annotate, layout } from "../renderer/layout";
import { reshape } from "../renderer/reshaper";
import { resolveSessionPath } from "./pick-session";

export interface RenderOptions {
  filePath?: string;
  output: string;
}

export async function render(opts: RenderOptions): Promise<void> {
  try {
    return await _render(opts);
  } catch (e) {
    process.stderr.write(`Error: ${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(1);
  }
}

async function _render(opts: RenderOptions): Promise<void> {
  const filePath = await resolveSessionPath(opts.filePath);

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
