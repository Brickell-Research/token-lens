import { existsSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { Parser } from "../parser";
import { annotate } from "../renderer/annotator";
import { Html } from "../renderer/html";
import { layout } from "../renderer/layout";
import { Reshaper } from "../renderer/reshaper";
import { activeOrLatestJsonl } from "../session";

export interface RenderOptions {
  filePath?: string;
  output: string;
}

export class Render {
  private opts: RenderOptions;

  constructor(opts: RenderOptions) {
    this.opts = opts;
  }

  async run(): Promise<void> {
    const filePath = this.resolvePath();
    process.stderr.write(`Rendering ${filePath}\n`);
    const tree = new Parser(filePath).parse();
    const reshapedTree = new Reshaper().reshape(tree);
    reshapedTree.sort((a, b) => (a.token.timestamp ?? "").localeCompare(b.token.timestamp ?? ""));
    annotate(reshapedTree);
    const canvasWidth = layout(reshapedTree);
    const html = new Html(canvasWidth).render(reshapedTree);
    writeFileSync(this.opts.output, html);
    console.log(`Wrote ${this.opts.output}`);
  }

  private resolvePath(): string {
    if (this.opts.filePath) {
      return this.opts.filePath;
    }

    const sessionsDir = join(homedir(), ".token-lens", "sessions");

    if (existsSync(sessionsDir)) {
      const files = readdirSync(sessionsDir)
        .filter((f) => f.endsWith(".json"))
        .map((f) => join(sessionsDir, f))
        .filter((p) => statSync(p).isFile());

      if (files.length > 0) {
        files.sort((a, b) => statSync(b).mtimeMs - statSync(a).mtimeMs);
        return files[0];
      }
    }

    process.stderr.write("No saved captures found — reading active Claude Code session directly\n");
    return activeOrLatestJsonl();
  }
}
