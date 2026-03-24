# Setup

Requires [Bun](https://bun.sh). Install deps: `bun install`

# Commands

- Dev run: `bun run dev`
- Tests: `bun test`
- Lint: `bun run lint`
- Type check: `bun run typecheck`
- Build binary: `bun run build`

# Architecture

- New CLI commands go in `src/commands/` as a class
- Register them in `src/index.ts` via Commander `.command()`
- Tests mirror src structure: `src/foo.ts` → `src/foo.test.ts`
- Renderer pipeline: `Parser` → `Reshaper` → sort → `annotate` → `layout` → `Html`
