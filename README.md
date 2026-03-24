# Token Lens

[![CI](https://github.com/Brickell-Research/token-lens/actions/workflows/ci.yml/badge.svg)](https://github.com/Brickell-Research/token-lens/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/Brickell-Research/token-lens)](https://github.com/Brickell-Research/token-lens/releases/latest)
[![GitHub downloads](https://img.shields.io/github/downloads/Brickell-Research/token-lens/total)](https://github.com/Brickell-Research/token-lens/releases)
[![Built with Bun](https://img.shields.io/badge/Built%20with-Bun-fbf0df?logo=bun)](https://bun.sh)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.8-3178c6?logo=typescript&logoColor=white)](https://www.typescriptlang.org)

Flame graphs for [Claude Code](https://claude.ai/code) token usage, grounded in a per-prompt heatmap colored by token count or estimated cost. Inspired by [Brendan Gregg's flame graphs](https://www.brendangregg.com/flamegraphs.html): if you squint, token stacks look a lot like CPU call stacks. The heatmap-plus-flame-graph combo is loosely based on [Netflix's FlameScope](https://github.com/Netflix/flamescope). If you use Claude Code heavily, you're probably already familiar with [CCUsage](https://ccusage.com/) — great for aggregate token and cost tracking. I use them in tandem; CCUsage for the totals, token-lens for the shape.

![Demo](docs/token-lens.gif)

## Install

```sh
brew tap Brickell-Research/caffeine
brew install token-lens
```

## Usage

Render a Claude Code session:

```sh
token-lens render
open flame.html
```

If you have multiple sessions, `render` shows an interactive picker. With only one session it auto-selects it.

Record a bounded window while you work:

```sh
token-lens record --duration-in-seconds=300 --output=session.json
# ... do your Claude Code work ...
token-lens render --file-path=session.json
open flame.html
```

### Options

```sh
token-lens record --output=my-session.json              # save to a specific path
token-lens record --project-dir=/path/to/project        # record a specific project's session
token-lens render --file-path=my-session.json           # render a specific capture
token-lens render --output=report.html                  # write HTML to a custom path
```

## License

[MIT](./LICENSE)
