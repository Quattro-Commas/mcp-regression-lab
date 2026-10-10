[![CI](https://github.com/Quattro-Commas/mcp-regression-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/Quattro-Commas/mcp-regression-lab/actions/workflows/ci.yml)
[![CodeQL](https://github.com/Quattro-Commas/mcp-regression-lab/actions/workflows/codeql.yml/badge.svg)](https://github.com/Quattro-Commas/mcp-regression-lab/actions/workflows/codeql.yml)
[![License: ISC](https://img.shields.io/badge/License-ISC-blue.svg)](https://opensource.org/licenses/ISC)
[![Node >=24](https://img.shields.io/badge/node-%3E%3D24-brightgreen.svg)](https://nodejs.org/)

# mcp-regression-lab

Catch MCP releases that silently break agents. Snapshot a remote MCP server's
tool contract, diff it against the last release, lint it for things that hurt
tool selection, and re-run golden "prompt → expected tool" tests on a local
model.

## The problem

MCP servers ship new tool versions that silently break agent integrations: a
tool gets renamed, an argument becomes required, a description shrinks to
nothing. The agent still connects but starts making wrong tool calls. No one
catches it until users complain.

## Quick start (Node >= 24, no build step)

```sh
npm install
node src/cli.ts snapshot https://example.com/mcp -o baseline.json
node src/cli.ts lint baseline.json
# ...after the next release:
node src/cli.ts snapshot https://example.com/mcp -o current.json
node src/cli.ts diff baseline.json current.json          # exit 1 = breaking
node src/cli.ts golden current.json cases.json --model qwen3 --repeat 3 -o golden.json
node src/cli.ts report baseline.json current.json --golden golden.json -o report.html
```

Golden cases (`examples/cases.json`):
`{ "id", "prompt", "expectTool", "requiredArgs"?: string[], "forbiddenTools"?: string[] }`

## What it checks

Three layers of regression detection:

- **Deterministic**: contract diff (tool removed/renamed, argument type change,
  required ↔ optional, new required argument, description change). `diff` exits
  1 on breaking changes, so it can gate CI.
- **Heuristic**: hygiene lint (thin descriptions, untyped/undocumented args,
  injection-like text).
- **Probabilistic**: golden tool-selection tests via Ollama, N runs each,
  reported as pass rates. The model is only asked which tool it _would_ call;
  the server's tools are never executed.

Remote streamable-HTTP servers only. Bearer token via `MCP_TOKEN` env var; it
is never written to disk, and URL query strings are stripped from saved
contracts.

## Demo

```sh
node examples/demo-server.ts v1   # prints a local URL; v2 simulates a careless release
```

## Architecture

```mermaid
flowchart LR
    subgraph Snapshot["snapshot"]
        S[HTTP MCP Server] --> C[Contract JSON]
    end

    subgraph Analysis["analysis"]
        C --> D[Diff]
        C --> L[Lint]
        C --> G[Golden Tests]
        G --> O[Ollama (local)]
    end

    subgraph Output["output"]
        D --> R[Report]
        L --> R
        G --> R
    end

    subgraph CI["GitHub Action"]
        R --> PR[PR Comment]
        R --> Check[Check Status]
    end
```

The CLI snapshots a live MCP server's tool contract, then runs deterministic
diff + heuristic lint + probabilistic golden tests against it. The GitHub Action
wraps this so a customer's CI catches regressions before merge.

## Key design decisions

- **Never executes server tools**: the golden tests only ask which tool the
  model _would_ call. No side effects on the target server.
- **Deterministic core**: diff and lint are fully deterministic. Golden tests
  are probabilistic but repeatable with `--repeat N`.
- **Local model for golden tests**: uses Ollama so no API keys are needed for
  the probabilistic layer. The model is only asked about tool selection, not
  asked to generate code.
- **No SDK dependency for GitHub integration**: the PR comment is posted with
  plain `fetch` against the GitHub REST API.

## Development

```sh
npm run build   # tsc type check
npm test        # node:test, includes real HTTP MCP fixture servers
```

## GitHub Action

Wraps the same CLI so a customer's own CI catches a contract regression before
merge, with no hosting on your side (`action.yml`, composite action, runs
inside their runner):

```yaml
# .github/workflows/mcp-contract.yml (customer's repo)
on: pull_request
permissions: { pull-requests: write }
jobs:
  contract-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: Quattro-Commas/mcp-regression-lab@v1
        with:
          mcp-url: https://your-mcp-server.example.com/mcp
          baseline: .mcp-contract.json # commit this once via `snapshot`
```

It snapshots the live server, diffs + lints against the committed baseline,
posts/updates one PR comment, and **fails the check on any breaking change**.

**Hosted mode** — approved baseline + golden tests, managed at
https://mcp-regression-lab.vercel.app:

```yaml
- uses: Quattro-Commas/mcp-regression-lab@v1
  with:
    api-token: ${{ secrets.MCP_REGRESSION_LAB_TOKEN }}
    server-id: <id from the server's dashboard URL>
```

Fails on a breaking change or a golden-test pass-rate drop. Outputs:
`breaking-changes`, `golden-regressions`.

### Version selection

- `@v1` follows the latest backwards-compatible v1 release.
- `@v1.0.0` pins the current synced release.
- Pin to a full commit SHA for strongest dependency-integrity control.

## Limitations

- **Streamable-HTTP only**: stdio MCP servers are not supported. The server
  must be reachable over HTTP.
- **Ollama required for golden tests**: the deterministic diff/lint layers work
  without Ollama, but golden tests need a local model.
- **Golden test variance**: pass rates can vary between model versions. Use
  `--repeat N` to smooth out noise.
- **No auto-fix**: reports regressions but does not fix them. The PR comment
  tells you what changed; you decide what to do.

## Security and support

Do not include MCP tokens, model keys, API tokens, or server credentials in
issues, pull requests, or contract artifacts. Read [SECURITY.md](SECURITY.md)
before reporting a vulnerability and [CONTRIBUTING.md](CONTRIBUTING.md) before
proposing a change.

## License

ISC — see [LICENSE](LICENSE).
