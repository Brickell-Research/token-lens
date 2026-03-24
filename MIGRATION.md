# Migration Plan: Ruby → TypeScript + Bun

## Overview

Migrating from Ruby (Thor CLI gem) to TypeScript with Bun as both runtime and binary compiler.
Target: `bun build --compile` → single self-contained binary, no runtime dependency.

---

## Phase 0: Bootstrap

**Remove Ruby artifacts:**
```
Gemfile  Gemfile.lock  token-lens.gemspec  Rakefile
.ruby-version  .rspec  .solargraph.yml
```

**Install Bun:** https://bun.sh/docs/installation

**Initialize project:**
```bash
bun init -y
bun add commander
bun add -d typescript @tsconfig/bun @types/bun @biomejs/biome
```

**`tsconfig.json`:**
```json
{
  "extends": "@tsconfig/bun/tsconfig.json",
  "compilerOptions": {
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "noEmit": true
  },
  "include": ["src"]
}
```

**`biome.json`:**
```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "organizeImports": { "enabled": true },
  "linter": { "enabled": true, "rules": { "recommended": true } },
  "formatter": { "enabled": true, "indentStyle": "space", "indentWidth": 2 }
}
```

**`package.json` scripts:**
```json
{
  "scripts": {
    "dev": "bun run src/index.ts",
    "build": "bun build --compile src/index.ts --outfile dist/token-lens --minify",
    "test": "bun test",
    "typecheck": "tsc --noEmit",
    "lint": "biome check --write .",
    "lint:check": "biome check .",
    "ci": "bun run typecheck && bun run lint:check && bun test"
  },
  "bin": { "token-lens": "dist/token-lens" }
}
```

---

## File Structure Map

```
Ruby                                      TypeScript
lib/token_lens/version.rb             →  package.json "version"
lib/token_lens/pricing.rb             →  src/pricing.ts
lib/token_lens/tokens/jsonl.rb        →  src/token.ts
lib/token_lens/session.rb             →  src/session.ts
lib/token_lens/sources/jsonl.rb       →  src/sources/jsonl.ts
lib/token_lens/parser.rb              →  src/parser.ts
lib/token_lens/renderer/annotator.rb  →  src/renderer/annotator.ts
lib/token_lens/renderer/reshaper.rb   →  src/renderer/reshaper.ts
lib/token_lens/renderer/layout.rb     →  src/renderer/layout.ts
lib/token_lens/renderer/html.rb       →  src/renderer/html.ts
lib/token_lens/renderer/html.css      →  src/renderer/html.css   (unchanged)
lib/token_lens/renderer/html.js       →  src/renderer/html.js    (unchanged)
lib/token_lens/commands/record.rb     →  src/commands/record.ts
lib/token_lens/commands/render.rb     →  src/commands/render.ts
lib/token_lens/cli.rb                 →  src/index.ts
bin/token-lens                        →  src/index.ts (entry point)
spec/                                 →  src/**/*.test.ts
```

---

## Naming Conventions

All Ruby snake_case identifiers become camelCase in TypeScript:

| Ruby | TypeScript |
|------|-----------|
| `subtree_tokens` | `subtreeTokens` |
| `parent_uuid` | `parentUuid` |
| `is_sidechain` | `isSidechain` |
| `marginal_input_tokens` | `marginalInputTokens` |
| `cache_read_tokens` | `cacheReadTokens` |
| `cache_creation_tokens` | `cacheCreationTokens` |
| `is_compaction` | `isCompaction` |
| `is_human_prompt?` | `isHumanPrompt(token)` |
| `node[:token]` | `node.token` |
| `node[:children]` | `node.children` |

JSON keys from Claude Code JSONL files are already camelCase (`parentUuid`, `requestId`) — no change needed there.

---

## Shared Types (src/types.ts) — Create First

```typescript
export interface Token {
  readonly uuid: string | null;
  readonly parentUuid: string | null;
  readonly requestId: string | null;
  readonly type: string;
  readonly role: string | null;
  readonly model: string | null;
  readonly isSidechain: boolean;
  readonly agentId: string | null;
  readonly content: (string | ContentBlock)[];
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cacheReadTokens: number;
  readonly cacheCreationTokens: number;
  readonly marginalInputTokens: number;
  readonly timestamp: string | null;
  readonly isCompaction: boolean;
}

export interface ContentBlock {
  type: "text" | "tool_use" | "tool_result" | string;
  id?: string;
  name?: string;
  input?: Record<string, unknown>;
  content?: unknown;
  text?: string;
}

// Annotated node — fields added progressively by each pipeline stage
export interface Node {
  token: Token;
  children: Node[];
  // Added by Annotator:
  depth?: number;
  subtreeTokens?: number;
  subtreeCost?: number;
  // Added by Layout:
  x?: number;
  y?: number;
  w?: number;
  costX?: number;
  costW?: number;
  // Added by Html renderer:
  alt?: boolean;
}

export interface Rate {
  input: number;
  cacheRead: number;
  cacheCreation: number;
  output: number;
}

export interface RawEvent {
  uuid?: string;
  parentUuid?: string;
  requestId?: string;
  type?: string;
  timestamp?: string;
  parentToolUseID?: string;
  message?: RawMessage;
  data?: {
    type?: string;
    agentId?: string;
    message?: {
      uuid?: string;
      requestId?: string;
      type?: string;
      message?: RawMessage;
    };
  };
}

export interface RawMessage {
  role?: string;
  model?: string;
  content?: unknown;
  usage?: {
    input_tokens?: number;
    output_tokens?: number;
    cache_read_input_tokens?: number;
    cache_creation_input_tokens?: number;
  };
}
```

---

## Phase 1: src/pricing.ts

Straightforward lookup table. Ruby's `for_model` prefix-matching loop translates directly.

**Key translation:**
- `TABLE = [...].freeze` → `const PRICING_TABLE: [string, Rate][] = [...]`
- `TABLE.find { |prefix, _| model&.start_with?(prefix) }&.last` → `PRICING_TABLE.find(([p]) => model?.startsWith(p))?.[1]`
- Module with `self.for_model` → exported function `getRatesForModel(model: string | null): Rate`

---

## Phase 2: src/token.ts

Ruby's `Tokens::Jsonl` is a `Data.define(...)` immutable value class. In TypeScript, split it into:
1. The `Token` interface (in `types.ts`)
2. `createToken(raw: RawEvent): Token` factory function
3. Standalone computed functions (avoids class overhead, easier testing)
4. `withToken(t: Token, overrides: Partial<Token>): Token` = `{ ...t, ...overrides }`

**Key computed functions to port:**
```typescript
costUsd(token: Token): number
totalTokens(token: Token): number
displayWidth(token: Token): number
isHumanPrompt(token: Token): boolean
isTaskNotification(token: Token): boolean
taskNotificationSummary(token: Token): string | null
humanText(token: Token): string
toolUses(token: Token): ContentBlock[]
toolResults(token: Token): ContentBlock[]
```

**Key translation patterns:**
- `Array(msg["content"])` → `Array.isArray(c) ? c : c == null ? [] : [c]`
- `usage["input_tokens"].to_i` → `usage?.input_tokens ?? 0`
- `.select { |b| b.is_a?(Hash) && b["type"] == "tool_use" }` → `.filter(b => typeof b === 'object' && b.type === 'tool_use')`

---

## Phase 3: src/session.ts

Pure utility functions. Uses `node:fs`, `node:path`, `node:os`.

**Key translations:**
- `Pathname.new("~/.claude/projects").expand_path` → `path.join(os.homedir(), '.claude', 'projects')`
- `dir.gsub(/[^a-zA-Z0-9]/, "-")` → `dir.replace(/[^a-zA-Z0-9]/g, '-')`
- `Dir.glob(...)` → `fs.readdirSync(...)` + filter for `.jsonl`
- Sort by mtime: `files.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs)`
- `Session.tail` infinite loop → async generator function or callback with `setInterval`

**The tail function** (used by record command): Poll every 100ms, track file position via `lastPos`, read new bytes on each tick.

```typescript
export async function* tail(filePath: string): AsyncGenerator<RawEvent> {
  let lastPos = (await Bun.file(filePath).size);
  while (true) {
    const size = Bun.file(filePath).size;
    if (size > lastPos) {
      // read new lines from lastPos to size
    }
    await Bun.sleep(100);
  }
}
```

---

## Phase 4: src/sources/jsonl.ts

Queue-based producer. In TypeScript, the Ruby `Queue` + producer thread pattern maps to an async generator (simpler and idiomatic in Bun):

```typescript
export async function* streamJsonl(projectDir?: string): AsyncGenerator<{ source: "jsonl"; event: RawEvent }> {
  const path = projectDir ? activeJsonl(projectDir) : activeOrLatestJsonl();
  for await (const event of tail(path)) {
    yield { source: "jsonl", event };
  }
}
```

---

## Phase 5: src/parser.ts

The 5-phase algorithm translates directly. ~190 lines in Ruby, will be ~190 lines in TypeScript.

**Key translation patterns:**

| Ruby | TypeScript |
|------|-----------|
| `Hash.new { \|h, k\| h[k] = [] }` | `new Map<string, T[]>()` with helper `getOrInit(map, key, [])` |
| `each_with_object({}) { \|t, h\| h[t.uuid] = ... }` | `tokens.reduce((acc, t) => { acc[t.uuid!] = ...; return acc; }, {} as Record<string, Node>)` |
| `index.each_value do \|node\|` | `Object.values(index).forEach(node => ...)` |
| `parent_uuid && index[parent_uuid]` | `parentUuid && index[parentUuid]` |
| `[].any? { \|n\| remove_node(n[:children], target) }` | `nodes.some(n => removeNode(n.children, target))` |

**JSON format detection** (same logic):
```typescript
const isCapture = content.trimStart().startsWith('[');
const rawEvents: RawEvent[] = isCapture
  ? (JSON.parse(content) as Array<{ event: RawEvent }>).map(e => e.event)
  : content.split('\n').flatMap(line => { try { return [JSON.parse(line)]; } catch { return []; } });
```

---

## Phase 6: src/renderer/annotator.ts

19 lines in Ruby, ~25 in TypeScript. Post-order recursive traversal mutating nodes in-place.

```typescript
export function annotate(nodes: Node[], depth = 0): void {
  for (const node of nodes) {
    annotate(node.children, depth + 1);
    node.depth = depth;
    node.subtreeTokens = Math.max(displayWidth(node.token), 1) +
      node.children.reduce((s, c) => s + (c.subtreeTokens ?? 0), 0);
    node.subtreeCost = costUsd(node.token) +
      node.children.reduce((s, c) => s + (c.subtreeCost ?? 0), 0);
  }
}
```

---

## Phase 7: src/renderer/reshaper.ts

110 lines in Ruby. The most stateful piece: `@pending_roots` becomes a class field.

**Key translations:**
- `node.merge(children: siblings)` → `{ ...node, children: siblings }`
- `t.with(marginal_input_tokens: marginal, is_compaction: compaction)` → `withToken(t, { marginalInputTokens: marginal, isCompaction: compaction })`
- `nodes.flat_map { |node| ... }` → `nodes.flatMap(node => ...)`
- The `@pending_roots` instance variable: use a class with a field, or pass as a parameter

Use a class to mirror Ruby's instance variable pattern:

```typescript
export class Reshaper {
  private pendingRoots: Node[] = [];

  reshape(nodes: Node[]): Node[] {
    // ...
  }
}
```

---

## Phase 8: src/renderer/layout.ts

61 lines in Ruby. All mutations (setting `x`, `y`, `w`, `costX`, `costW`) stay as in-place mutations on `Node` objects (already mutability-friendly with the interface design above).

---

## Phase 9: src/renderer/html.ts

The 1050-line centerpiece. Mostly mechanical substitution:
- `<<~HTML ... HTML` heredocs → `` `...` `` template literals
- `#{expr}` → `${expr}`
- `"$%.4f" % val` → `val.toFixed(4)`
- `str.gsub(/\n/, "\\n")` → `str.replace(/\n/g, '\\n')`
- `[].sum { |n| n[:x] }` → `arr.reduce((s, n) => s + n.x!, 0)`

**Static assets (html.css, html.js):** Move to `src/renderer/`. Read at render time using Bun's embedded file API so they bundle correctly into the compiled binary:

```typescript
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// Works in both dev (file read) and compiled binary (bundled by Bun):
const css = await Bun.file(new URL("./html.css", import.meta.url)).text();
const js  = await Bun.file(new URL("./html.js",  import.meta.url)).text();
```

`html.css` and `html.js` do **not** need to be ported — they are already vanilla CSS/JS and stay unchanged.

**Ruby enumerables to watch:**
| Ruby | TypeScript |
|------|-----------|
| `.sum { \|n\| expr }` | `.reduce((s, n) => s + expr, 0)` |
| `.count { \|n\| cond }` | `.filter(n => cond).length` |
| `.any? { \|n\| cond }` | `.some(n => cond)` |
| `.compact` | `.filter(x => x != null)` |
| `.uniq { \|x\| x.id }` | `[...new Map(arr.map(x => [x.id, x])).values()]` |
| `.max_by { \|n\| n[:x] }` | `arr.reduce((max, n) => n.x! > max.x! ? n : max)` |
| `n.clamp(0, 255)` | `Math.max(0, Math.min(255, n))` |
| `"$%.2f" % usd` | `` `$${usd.toFixed(2)}` `` |

---

## Phase 10: src/commands/record.ts

The Ruby threading model (producer thread + drain thread + main timer) maps to Bun async:

```typescript
export class Record {
  async run() {
    const events: RawEvent[] = [];
    const source = streamJsonl(this.opts.projectDir);

    // Collect events until duration expires
    const deadline = Date.now() + this.opts.durationInSeconds * 1000;
    for await (const { event } of source) {
      events.push(event);
      if (Date.now() >= deadline) break;
    }

    // Write output
    await fs.mkdir(outputDir, { recursive: true });
    await Bun.write(outputPath, JSON.stringify(events.map(e => ({ event: e }))));
    console.log(`Saved ${events.length} events to ${outputPath}`);
  }
}
```

Signal handling (INT/TERM): use `process.on('SIGINT', finish)`.

---

## Phase 11: src/commands/render.ts

The 6-stage pipeline:
```typescript
export class Render {
  async run() {
    const filePath = this.opts.filePath ?? resolveLatestCapture();
    const tree = new Parser(filePath).parse();
    new Reshaper().reshape(tree);           // mutates → new roots returned
    tree.sort((a, b) => (a.token.timestamp ?? "").localeCompare(b.token.timestamp ?? ""));
    annotate(tree);
    const canvasWidth = layout(tree);
    const html = new Html(canvasWidth).render(tree);
    await Bun.write(this.opts.output, html);
    console.log(`Wrote ${this.opts.output}`);
  }
}
```

File resolution: glob `~/.token-lens/sessions/*.json`, sort by mtime, pick newest. Falls back to live JSONL session.

---

## Phase 12: src/index.ts (CLI entry point)

```typescript
#!/usr/bin/env bun
import { Command } from 'commander';
import { Record } from './commands/record.js';
import { Render } from './commands/render.js';

const program = new Command();
program.name('token-lens').description('Flame graphs for Claude Code token usage');

program.command('record')
  .description('Tail the active session and auto-save a capture file')
  .option('--duration-in-seconds <n>', 'Seconds to record', '30')
  .option('--project-dir <path>', 'Working directory of the Claude Code session')
  .option('--output <path>', 'Save path for the capture')
  .action(opts => new Record({
    durationInSeconds: parseInt(opts.durationInSeconds),
    projectDir: opts.projectDir,
    output: opts.output,
  }).run());

program.command('render')
  .description('Render a captured session as a flame graph')
  .option('--file-path <path>', 'Path to the captured JSON file')
  .option('--output <path>', 'Output HTML path', 'flame.html')
  .action(opts => new Render({ filePath: opts.filePath, output: opts.output }).run());

program.parse();
```

---

## Phase 13: Tests (spec/ → src/**/*.test.ts)

Migrate from RSpec to Bun's built-in test runner. API is nearly identical.

| RSpec | Bun test |
|-------|---------|
| `RSpec.describe Foo do` | `describe('Foo', () => {` |
| `it "does thing" do` | `it('does thing', () => {` |
| `expect(x).to eq(y)` | `expect(x).toBe(y)` |
| `expect(x).to eq([...])` | `expect(x).toEqual([...])` |
| `expect { ... }.to raise_error` | `expect(() => ...).toThrow()` |
| `let(:foo) { ... }` | `const foo = ...` or `beforeEach` |
| `allow(x).to receive(:y).and_return(z)` | `spyOn(x, 'y').mockReturnValue(z)` |

Test files: mirror the source structure → `src/pricing.test.ts`, `src/token.test.ts`, `src/parser.test.ts`, etc.

Run: `bun test` (auto-discovers `**/*.test.ts`).

---

## Phase 14: CI (.github/workflows/ci.yml)

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_requests:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: latest
      - run: bun install
      - run: bun run typecheck
      - run: bun run lint:check
      - run: bun test
      - run: bun run build
```

---

## Migration Order Summary

Execute in this order (each phase has no deps on later phases):

1. `src/types.ts` — shared interfaces (no imports)
2. `src/pricing.ts` — pure lookup table (no imports)
3. `src/token.ts` — factory + computed functions (imports: pricing, types)
4. `src/session.ts` — file discovery (imports: types, node:fs, node:path, node:os)
5. `src/sources/jsonl.ts` — async streaming (imports: session)
6. `src/parser.ts` — tree builder (imports: token, types)
7. `src/renderer/annotator.ts` — depth + cost annotation (imports: token, types)
8. `src/renderer/reshaper.ts` — tree reshape (imports: token, types)
9. `src/renderer/layout.ts` — pixel positioning (imports: types)
10. `src/renderer/html.ts` — HTML generation (imports: all renderer, token, pricing)
11. `src/commands/record.ts` — record command (imports: session, sources/jsonl)
12. `src/commands/render.ts` — render command (imports: parser, renderer/*)
13. `src/index.ts` — CLI entry point (imports: commands/*)
14. Migrate tests phase by phase alongside or after source files
15. Update CI

---

## Gotchas and Watch-outs

1. **`bun build --compile` binary size:** ~100MB. This is expected — the Bun runtime is embedded. The Ruby gem was small because Ruby is assumed installed; Bun produces a truly standalone binary.

2. **`html.css` and `html.js` embedding:** Use `new URL("./html.css", import.meta.url)` — Bun's bundler detects this pattern and embeds the files. Do NOT use `__dirname + "/html.css"` (breaks in compiled binaries).

3. **`bun build` doesn't type-check:** Always run `tsc --noEmit` in CI separately. Bun strips types without checking them.

4. **`Data.define`'s `with()` method:** In Ruby, nodes are mutated AND tokens use immutable `with()` copies. In TypeScript, keep the same pattern: mutate node fields directly (`node.depth = 0`), but use spread for token copies (`withToken(t, { isSidechain: true })`).

5. **`node[:token]` vs `node.token`:** All the `[:symbol]` hash accesses become `.property` dot access. Use non-null assertions (`!`) where you know the pipeline has populated the field (e.g., `node.x!` after Layout runs).

6. **Regex capture groups:** Ruby `match(...)[1]` → TypeScript `match(...)?.[1]`. Groups are 1-indexed in both.

7. **Integer division in layout:** Ruby's `.round` on floats is `Math.round()`. The cursor arithmetic must stay float until rounded — same as Ruby.

8. **`clamp` on number:** No built-in `Number.clamp` in JS. Use `Math.max(0, Math.min(255, n))` or add a helper.

9. **Polling in `record`:** The Ruby `Sources::Jsonl` reads the file from `last_pos` using `IO#seek`. In Bun: `Bun.file(path).slice(lastPos).text()` reads from an offset, or use `node:fs` `fs.openSync` + `fs.readSync` with an offset.

10. **`warn` writes to stderr:** `console.error()` in TypeScript (not `console.warn` which also goes to stderr but is semantically different).
