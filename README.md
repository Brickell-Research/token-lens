# Token Lens

Basically a combination of [perf](https://perfwiki.github.io/main/) plus [flame-graphs](https://www.brendangregg.com/flamegraphs.html) for local [claude-code](https://code.claude.com/docs/en/overview) usage.

## Architecture

```
Record Data --> Interpret Data --> Render Data
```

## Data Sources

1. Tap OTEL console output
2. Tail session JSONL
3. Local API proxy

## Contributing

Checkout [CONTRIBUTING.md](./CONTRIBUTING.md).

## License

[MIT](./LICENSE)
