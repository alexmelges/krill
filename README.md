# krill

Krill is a typed, local-first workflow runtime for coding-agent operations.

It provides deterministic step execution, explicit approval gates, and JSONL run logs for auditability.

## Status
M0/M1 scaffold is implemented:
- typed workflow model
- YAML/JSON parsing
- deterministic local runner
- `exec`, `echo`, and `approve` steps
- run logging to `.krill/runs/*.jsonl`

## Quickstart

### Build
```bash
cabal build
```

### Validate a workflow
```bash
cabal run krill -- validate --file examples/basic.krill.yaml
```

### Run a workflow
```bash
cabal run krill -- run --file examples/basic.krill.yaml --auto-approve
```

Without `--auto-approve`, `approve` steps require a TTY prompt; non-interactive runs fail closed.

## Workflow File Format
Krill accepts YAML or JSON with the same shape:

```yaml
name: basic
version: 1
steps:
  - kind: echo
    text: "hello"
  - kind: approve
    message: "Continue?"
  - kind: exec
    command: "echo done"
```

### Step Kinds
- `echo`: prints `text`
- `approve`: approval gate with optional `message`
- `exec`: executes shell `command`

## Run Logs
Each run writes line-delimited JSON events to:

```text
.krill/runs/<timestamp>.jsonl
```

Each line is a structured `RunLog` event containing timestamp, run id, step metadata, event type, and status.

## Tests
```bash
cabal test
```

## Documentation
- Architecture: `docs/ARCHITECTURE.md`
- Milestones: `docs/MILESTONES.md`

## Roadmap
- M0 Foundation
- M1 Deterministic local runtime
- M2 Validation + policy layer
- M3 Extensible step runtime
- M4 Reproducibility + distribution readiness
