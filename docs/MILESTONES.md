# Krill Milestones

This document tracks concrete delivery checklists for the first four milestones.

## M0: Foundation and Repo Skeleton

### Deliverables
- [x] Cabal project with executable and test-suite targets
- [x] `docs/ARCHITECTURE.md` published
- [x] `docs/MILESTONES.md` published
- [x] Core domain types introduced in `src/Krill/Types.hs`
- [x] CLI command surface defined (`run`, `validate`)
- [x] Test harness bootstrapped with Hspec

### Exit Criteria
- [x] `cabal build` succeeds
- [x] `cabal test` executes test suite

## M1: Deterministic Local Runtime MVP

### Deliverables
- [x] Workflow parser supports YAML and JSON input
- [x] Required schema fields validated (`name`, `steps`, valid step kind)
- [x] Runner executes steps deterministically in declared order
- [x] Step implementations: `echo`, `exec`, `approve`
- [x] Non-interactive approval fails unless `--auto-approve`
- [x] Interactive approval prompt when TTY is present
- [x] JSONL run logging under `.krill/runs/<timestamp>.jsonl`
- [x] Example workflow added at `examples/basic.krill.yaml`

### Exit Criteria
- [x] `krill validate --file examples/basic.krill.yaml` passes
- [x] `krill run --file examples/basic.krill.yaml --auto-approve` completes successfully
- [x] Unit tests cover parser and runner minimum behavior

## M2: Validation and Policy Layer

### Deliverables
- [ ] Add static validation pass independent from decode phase
- [ ] Enforce deterministic schema versioning and migration policy
- [ ] Add policy model for approval requirements by step category
- [ ] Add `krill validate --strict` mode for policy + semantic checks
- [ ] Add run-time policy decision logs with explicit reason codes

### Exit Criteria
- [ ] Invalid workflows fail with precise, user-facing diagnostics
- [ ] Policy-denied workflows fail before execution
- [ ] Test matrix covers policy allow/deny and strict validation paths

## M3: Extensible Step Runtime

### Deliverables
- [ ] Introduce typed step extension interface (`StepProvider`/plugin boundary)
- [ ] Add first extension step for coding-agent file operations
- [ ] Add structured step input/output envelopes
- [ ] Add per-step timeout and retry strategy model
- [ ] Add deterministic artifact directory layout for run outputs

### Exit Criteria
- [ ] Core runner executes built-in and extension steps uniformly
- [ ] Extension API is documented with compatibility constraints
- [ ] Integration tests cover extension loading and failure handling
