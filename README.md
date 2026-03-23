# Token Lens

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
