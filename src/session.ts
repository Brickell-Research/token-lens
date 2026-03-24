import { existsSync, readdirSync, statSync, openSync, readSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { RawEvent } from "./types";

export const CLAUDE_DIR = join(homedir(), ".claude", "projects");

export function encodedCwd(dir?: string): string {
  return (dir ?? process.cwd()).replace(/[^a-zA-Z0-9]/g, "-");
}

export function activeJsonl(dir?: string): string {
  const projectDir = join(CLAUDE_DIR, encodedCwd(dir));
  if (!existsSync(projectDir)) {
    throw new Error(`No session files found for ${dir ?? process.cwd()}`);
  }
  const files = readdirSync(projectDir)
    .filter((f) => f.endsWith(".jsonl"))
    .map((f) => ({ path: join(projectDir, f), mtime: statSync(join(projectDir, f)).mtimeMs }))
    .sort((a, b) => b.mtime - a.mtime);
  if (files.length === 0) {
    throw new Error(`No session files found for ${dir ?? process.cwd()}`);
  }
  return files[0].path;
}

export function latestJsonl(): string {
  if (!existsSync(CLAUDE_DIR)) {
    throw new Error(`No session files found in ${CLAUDE_DIR}`);
  }
  const files: { path: string; mtime: number }[] = [];
  for (const entry of readdirSync(CLAUDE_DIR)) {
    const subdir = join(CLAUDE_DIR, entry);
    if (!statSync(subdir).isDirectory()) continue;
    for (const file of readdirSync(subdir)) {
      if (!file.endsWith(".jsonl")) continue;
      const fullPath = join(subdir, file);
      files.push({ path: fullPath, mtime: statSync(fullPath).mtimeMs });
    }
  }
  if (files.length === 0) {
    throw new Error(`No session files found in ${CLAUDE_DIR}`);
  }
  files.sort((a, b) => b.mtime - a.mtime);
  return files[0].path;
}

export function activeOrLatestJsonl(dir?: string): string {
  try {
    return activeJsonl(dir);
  } catch {
    const path = latestJsonl();
    process.stderr.write(
      `  [session] no sessions for ${dir ?? process.cwd()}, using most recent: ${path}\n`
    );
    return path;
  }
}

export function tailFile(path: string, onLine: (event: RawEvent) => void): () => void {
  let lastPos = Bun.file(path).size;
  let stopped = false;

  const fd = openSync(path, "r");
  const buf = Buffer.allocUnsafe(65536);

  function poll() {
    if (stopped) return;
    const currentSize = Bun.file(path).size;
    if (currentSize > lastPos) {
      let pos = lastPos;
      let partial = "";
      while (pos < currentSize) {
        const bytesToRead = Math.min(buf.byteLength, currentSize - pos);
        const bytesRead = readSync(fd, buf, 0, bytesToRead, pos);
        if (bytesRead === 0) break;
        pos += bytesRead;
        partial += buf.toString("utf8", 0, bytesRead);
      }
      lastPos = pos;
      const lines = partial.split("\n");
      for (let i = 0; i < lines.length - 1; i++) {
        const line = lines[i].trim();
        if (line.length === 0) continue;
        try {
          onLine(JSON.parse(line) as RawEvent);
        } catch {
          // skip malformed lines
        }
      }
      // last element may be an incomplete line — discard (it will be re-read next poll)
      // but since we already advanced lastPos, we need to rewind by the leftover bytes
      const leftover = lines[lines.length - 1];
      if (leftover.length > 0) {
        lastPos -= Buffer.byteLength(leftover, "utf8");
      }
    }
    setTimeout(poll, 100);
  }

  poll();

  return () => {
    stopped = true;
  };
}
