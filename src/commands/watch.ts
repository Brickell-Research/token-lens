import { exec } from "node:child_process";
import { writeFileSync } from "node:fs";
import { parse } from "../parser";
import { Html } from "../renderer/html";
import { annotate, layout } from "../renderer/layout";
import { reshape } from "../renderer/reshaper";
import { activeJsonl, activeOrLatestJsonl } from "../session";
import { resolveSessionPath } from "./pick-session";

export interface WatchOptions {
  filePath?: string;
  output?: string;
  /** Auto-select the active live session (skips picker) */
  live?: boolean;
  /** Working directory of the Claude Code session (implies --live) */
  projectDir?: string;
  /** Browser reload interval in milliseconds (default: 2000) */
  intervalMs?: number;
}

export function renderHtml(filePath: string): string {
  const tree = parse(filePath);
  const reshapedTree = reshape(tree);
  reshapedTree.sort((a, b) => (a.token.timestamp ?? "").localeCompare(b.token.timestamp ?? ""));
  annotate(reshapedTree);
  const canvasWidth = layout(reshapedTree);
  return new Html(canvasWidth).render(reshapedTree);
}

export function injectAutoRefresh(html: string, intervalMs = 2000): string {
  const script = `<script>setInterval(function(){location.reload();},${intervalMs});</script>`;
  return html.replace("</body>", `${script}\n</body>`);
}

export async function watch(opts: WatchOptions): Promise<void> {
  const filePath = opts.projectDir
    ? activeJsonl(opts.projectDir)
    : opts.live
      ? activeOrLatestJsonl()
      : await resolveSessionPath(opts.filePath);
  const output = opts.output ?? "flame.html";
  const intervalMs = opts.intervalMs ?? 2000;

  function rerender() {
    try {
      const html = injectAutoRefresh(renderHtml(filePath), intervalMs);
      writeFileSync(output, html);
      process.stderr.write(`  re-rendered → ${output} (${Bun.file(filePath).size} bytes)\n`);
    } catch (e) {
      process.stderr.write(`  render error: ${e instanceof Error ? e.message : String(e)}\n`);
    }
  }

  // Initial render
  rerender();

  // Poll session file, debounce re-renders
  let lastSize = Bun.file(filePath).size;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  let stopped = false;

  function poll() {
    if (stopped) return;
    const size = Bun.file(filePath).size;
    if (size !== lastSize) {
      lastSize = size;
      if (debounceTimer !== null) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(rerender, 500);
    }
    setTimeout(poll, 200);
  }
  poll();

  process.stderr.write(`Watching  ${filePath}\n`);
  process.stderr.write(`Output    ${output}  (reloads every ${intervalMs}ms)\n`);
  process.stderr.write("Press Ctrl+C to stop.\n");

  // Open the file in the browser
  const fileUrl = `file://${require("node:path").resolve(output)}`;
  if (process.platform === "darwin") exec(`open ${fileUrl}`);
  else if (process.platform === "linux") exec(`xdg-open ${fileUrl}`);

  const shutdown = () => {
    stopped = true;
    if (debounceTimer !== null) clearTimeout(debounceTimer);
    process.stderr.write("\nStopped.\n");
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  await new Promise(() => {});
}
