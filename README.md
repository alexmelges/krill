# krill

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/alexmelges/krill/actions/workflows/ci.yml/badge.svg)](https://github.com/alexmelges/krill/actions/workflows/ci.yml)

**A typed workflow engine for coding agents.**

Coding agents need to run multi-step operations — build, test, deploy — with explicit checkpoints where a human can say "yes" or "no" before proceeding. Krill gives you a minimal, deterministic runtime for that: define workflows in YAML, execute them locally, get structured JSONL logs for every run. No daemons, no cloud, no YAML-as-programming-language. Just typed steps that run in order.

## Demo

```
$ krill run --file examples/basic.krill.yaml --auto-approve
Starting krill workflow
Krill executed command step
Workflow complete
Run completed successfully.
Run log: .krill/runs/20260227T080826455255000000Z.jsonl
```

## Installation

### Prerequisites

- **GHC** ≥ 9.14 ([ghcup](https://www.haskell.org/ghcup/) is the easiest way)
- **cabal** ≥ 3.0

### Build from source

```bash
git clone https://github.com/alexmelges/krill.git
cd krill
cabal build
```

The binary lands in `dist-newstyle/`. Run it directly:

```bash
cabal run krill -- run --file examples/basic.krill.yaml --auto-approve
```

Or install it to your PATH:

```bash
cabal install
```

## Usage

### Validate a workflow

```bash
krill validate --file workflow.krill.yaml
```

### Run a workflow

```bash
krill run --file workflow.krill.yaml
```

Without `--auto-approve`, approval gates prompt on the TTY. Non-interactive runs fail closed — this is intentional.

```bash
krill run --file workflow.krill.yaml --auto-approve
```

## Workflow Format Reference

Workflows are YAML or JSON files with this structure:

```yaml
name: my-workflow
version: 1
steps:
  - kind: echo
    name: greet          # optional
    text: "Hello"
  - kind: approve
    name: checkpoint     # optional
    message: "Continue?"
  - kind: exec
    name: build          # optional
    command: "make build"
```

### Top-level fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Workflow identifier |
| `version` | int | yes | Schema version (currently `1`) |
| `steps` | list | yes | Ordered list of steps |

### Step kinds

#### `echo`

Prints text to stdout. Useful for progress markers and status messages.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | `"echo"` | yes | Step type |
| `name` | string | no | Step identifier for logs |
| `text` | string | yes | Text to print |

#### `approve`

Approval gate. Blocks execution until a human confirms (or `--auto-approve` is set). If declined or no TTY is available, the run fails immediately.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | `"approve"` | yes | Step type |
| `name` | string | no | Step identifier for logs |
| `message` | string | yes | Prompt shown to the operator |

#### `exec`

Runs a shell command. Fails the workflow if the command exits non-zero.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `kind` | `"exec"` | yes | Step type |
| `name` | string | no | Step identifier for logs |
| `command` | string | yes | Shell command to execute |

## Run Logs

Every run produces a JSONL file at `.krill/runs/<timestamp>.jsonl`. Each line is a structured event:

```json
{"timestamp":"...","runId":"...","workflow":"basic","stepIndex":0,"stepName":"announce","event":"step_start","message":"..."}
```

These logs are append-only and machine-readable — designed for agent tooling to consume.

## Examples

See [`examples/`](examples/) for workflow files:

- [`basic.krill.yaml`](examples/basic.krill.yaml) — minimal echo + approve + exec
- [`build-pipeline.krill.yaml`](examples/build-pipeline.krill.yaml) — multi-step build/test/package pipeline
- [`deploy-with-gates.krill.yaml`](examples/deploy-with-gates.krill.yaml) — deployment with approval checkpoints

## Why Haskell?

Workflow engines are about correctness — you really don't want your deployment pipeline to silently do the wrong thing. Haskell's type system makes illegal states unrepresentable: every step kind is a distinct constructor, every workflow is parsed into a typed AST before execution, and the compiler catches whole categories of bugs that would be runtime surprises elsewhere.

It's also a single static binary with no runtime dependencies. No Python virtualenvs, no Node modules, no Docker. Just the binary.

## Tests

```bash
cabal test
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Milestones](docs/MILESTONES.md)
- [Contributing](CONTRIBUTING.md)

## Roadmap

- **M0** Foundation ✅
- **M1** Deterministic local runtime ✅
- **M2** Validation + policy layer
- **M3** Extensible step runtime
- **M4** Reproducibility + distribution readiness

## License

MIT — see [LICENSE](LICENSE).
