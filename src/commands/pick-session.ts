import { homedir } from "node:os";
import { basename, dirname } from "node:path";
import { createInterface } from "node:readline";
import { listAllSessions, type SessionEntry } from "../session";

const MAX_PICKER = 10;

function relativeTime(ms: number): string {
  const diff = Date.now() - ms;
  if (diff < 60_000) return "just now";
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)}m ago`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)}h ago`;
  if (diff < 7 * 86_400_000) return `${Math.floor(diff / 86_400_000)}d ago`;
  return new Date(ms).toLocaleDateString();
}

function humanSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1_048_576) return `${(bytes / 1024).toFixed(0)}KB`;
  return `${(bytes / 1_048_576).toFixed(1)}MB`;
}

export function sessionLabel(entry: SessionEntry): string {
  if (entry.source === "capture") {
    const stem = basename(entry.path, ".json");
    const ts = parseInt(stem, 10);
    if (!Number.isNaN(ts) && ts > 0) {
      return new Date(ts).toLocaleString(undefined, {
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
      });
    }
    return stem;
  }
  const encodedDir = basename(dirname(entry.path));
  const encodedHome = homedir().replace(/[^a-zA-Z0-9]/g, "-");
  if (encodedDir === encodedHome) return "~";
  if (encodedDir.startsWith(`${encodedHome}-`)) {
    return encodedDir.slice(encodedHome.length + 1);
  }
  return encodedDir;
}

export async function pickSession(sessions: SessionEntry[]): Promise<string> {
  const shown = sessions.slice(0, MAX_PICKER);
  const rest = sessions.length - shown.length;
  const LABEL_W = 34;
  const AGE_W = 10;

  process.stderr.write("\nAvailable sessions:\n");
  for (let i = 0; i < shown.length; i++) {
    const s = shown[i];
    const idx = String(i + 1).padStart(2);
    const kind = s.source.padEnd(7);
    const label = sessionLabel(s).slice(0, LABEL_W).padEnd(LABEL_W);
    const age = relativeTime(s.mtimeMs).padEnd(AGE_W);
    const size = humanSize(s.size);
    process.stderr.write(`  ${idx}  ${kind}  ${label}  ${age}  ${size}\n`);
  }
  if (rest > 0) {
    process.stderr.write(`       ... and ${rest} older (use --file-path to specify any)\n`);
  }
  process.stderr.write("\n");

  const rl = createInterface({ input: process.stdin, output: process.stderr });

  return new Promise<string>((resolve, reject) => {
    let resolved = false;
    rl.once("close", () => {
      if (!resolved) reject(new Error("No session selected."));
    });
    const ask = () => {
      rl.question("Pick [1]: ", (answer) => {
        const raw = answer.trim();
        const n = raw === "" ? 1 : parseInt(raw, 10);
        if (!Number.isNaN(n) && n >= 1 && n <= shown.length) {
          resolved = true;
          rl.close();
          resolve(shown[n - 1].path);
        } else {
          process.stderr.write(`  Please enter 1–${shown.length}\n`);
          ask();
        }
      });
    };
    ask();
  });
}

export async function resolveSessionPath(filePath?: string): Promise<string> {
  if (filePath) return filePath;

  const sessions = listAllSessions();
  if (sessions.length === 0) {
    throw new Error("No sessions found. Run `token-lens record` first, or pass --file-path.");
  }
  if (sessions.length === 1 || !process.stderr.isTTY) {
    if (sessions.length > 1) {
      process.stderr.write(
        `Non-interactive: auto-selected most recent of ${sessions.length} sessions\n`,
      );
    }
    return sessions[0].path;
  }
  return pickSession(sessions);
}
