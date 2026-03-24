import { existsSync, readdirSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { RawEvent } from "./types";

export const CLAUDE_DIR = join(homedir(), ".claude", "projects");
export const SESSIONS_DIR = join(homedir(), ".token-lens", "sessions");

export interface SessionEntry {
  path: string;
  source: "capture" | "live";
  mtimeMs: number;
  size: number;
}

export function listAllSessions(): SessionEntry[] {
  const entries: SessionEntry[] = [];

  if (existsSync(SESSIONS_DIR)) {
    for (const f of readdirSync(SESSIONS_DIR)) {
      if (!f.endsWith(".json")) continue;
      const p = join(SESSIONS_DIR, f);
      const s = statSync(p);
      if (s.isFile())
        entries.push({ path: p, source: "capture", mtimeMs: s.mtimeMs, size: s.size });
    }
  }

  if (existsSync(CLAUDE_DIR)) {
    for (const f of new Bun.Glob("**/*.jsonl").scanSync(CLAUDE_DIR)) {
      const p = join(CLAUDE_DIR, f);
      const s = statSync(p);
      entries.push({ path: p, source: "live", mtimeMs: s.mtimeMs, size: s.size });
    }
  }

  return entries.sort((a, b) => b.mtimeMs - a.mtimeMs);
}

export function encodedCwd(dir?: string): string {
  return (dir ?? process.cwd()).replace(/[^a-zA-Z0-9]/g, "-");
}

export function activeJsonl(dir?: string): string {
  const projectDir = join(CLAUDE_DIR, encodedCwd(dir));
  const files = existsSync(projectDir)
    ? Array.from(new Bun.Glob("*.jsonl").scanSync(projectDir))
        .map((f) => ({ path: join(projectDir, f), mtime: statSync(join(projectDir, f)).mtimeMs }))
        .sort((a, b) => b.mtime - a.mtime)
    : [];
  if (!files.length) throw new Error(`No session files found for ${dir ?? process.cwd()}`);
  return files[0].path;
}

export function latestJsonl(): string {
  const files = existsSync(CLAUDE_DIR)
    ? Array.from(new Bun.Glob("**/*.jsonl").scanSync(CLAUDE_DIR))
        .map((f) => ({ path: join(CLAUDE_DIR, f), mtime: statSync(join(CLAUDE_DIR, f)).mtimeMs }))
        .sort((a, b) => b.mtime - a.mtime)
    : [];
  if (!files.length) throw new Error(`No session files found in ${CLAUDE_DIR}`);
  return files[0].path;
}

export function activeOrLatestJsonl(dir?: string): string {
  try {
    return activeJsonl(dir);
  } catch {
    const path = latestJsonl();
    process.stderr.write(
      `  [session] no sessions for ${dir ?? process.cwd()}, using most recent: ${path}\n`,
    );
    return path;
  }
}

export function tailFile(path: string, onLine: (event: RawEvent) => void): () => void {
  let pos = Bun.file(path).size;
  let stopped = false;
  let partial = "";

  function poll() {
    if (stopped) return;
    const size = Bun.file(path).size;
    if (size > pos) {
      const chunk = Bun.file(path).slice(pos, size);
      pos = size;
      void chunk.text().then((text) => {
        partial += text;
        const lines = partial.split("\n");
        partial = lines.pop() ?? "";
        for (const line of lines) {
          if (!line.trim()) continue;
          try {
            onLine(JSON.parse(line) as RawEvent);
          } catch {}
        }
        setTimeout(poll, 100);
      });
      return;
    }
    setTimeout(poll, 100);
  }

  poll();
  return () => {
    stopped = true;
  };
}
