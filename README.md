# Token Lens

[![Gem Version](https://img.shields.io/gem/v/token-lens)](https://rubygems.org/gems/token-lens)
[![Gem Downloads](https://img.shields.io/gem/dt/token-lens)](https://rubygems.org/gems/token-lens)
[![CI](https://github.com/Brickell-Research/token-lens/actions/workflows/ci.yml/badge.svg)](https://github.com/Brickell-Research/token-lens/actions/workflows/ci.yml)
[![Ruby >= 3.2](https://img.shields.io/badge/Ruby-%3E%3D3.2-red?logo=ruby&logoColor=white)](https://www.ruby-lang.org/)
[![Standard](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/standardrb/standard)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Basically a combination of [perf](https://perfwiki.github.io/main/) plus [flame-graphs](https://www.brendangregg.com/flamegraphs.html) for local [claude-code](https://code.claude.com/docs/en/overview) usage.

## Architecture

```
Record Data --> Interpret Data --> Render Data
```

## Data Sources

1. [unsupported] Tap OTEL console output
2. [supported] Tail session JSONL
3. [unsupported] Local API proxy

## Quick Start

### Zero setup — render any session right now

No recording needed. token-lens reads directly from Claude Code's session files:

```
gem install token-lens
token-lens render
open flame.html
```

That's it. `render` with no arguments finds your most recent Claude Code session and renders it as a flame graph — no prior setup, no capture file, no extra terminal.

### Record a live session

If you want to capture a bounded window while you work (useful for comparing before/after):

```
token-lens record --duration-in-seconds=60
# ... do your Claude Code work in another terminal ...
token-lens render
open flame.html
```

Captures auto-save to `~/.token-lens/sessions/<timestamp>.json`. `render` always picks the most recent capture first, then falls back to the live session JSONL if no captures exist.

### Options

```
token-lens record --duration-in-seconds=300   # record for 5 minutes
token-lens record --output=my-session.json    # save to a specific path
token-lens render --file-path=my-session.json # render a specific capture
token-lens render --output=report.html        # write HTML to a custom path
```

### Locally

```
bin/token-lens render
open flame.html
```

## Contributing

Checkout [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
