import type { RawEvent } from "../types";
import { activeJsonl, activeOrLatestJsonl, tailFile } from "../session";

export interface JsonlSourceOptions {
  projectDir?: string;
  onEvent: (event: RawEvent) => void;
}

export function startJsonlSource(opts: JsonlSourceOptions): () => void {
  const path = opts.projectDir
    ? activeJsonl(opts.projectDir)
    : activeOrLatestJsonl();
  console.error(`Recording: ${path}`);
  return tailFile(path, opts.onEvent);
}
