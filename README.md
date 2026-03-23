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


**Locally**:
```
bin/token-lens record --duration-in-seconds=30 > capture.json
bin/token-lens render --file-path=capture.json
open flame.html
```

**Via gem**:
```
gem install token-lens
token-lens record --duration-in-seconds=30 > capture.json
token-lens render --file-path=capture.json
open flame.html
```

## Contributing

Checkout [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
