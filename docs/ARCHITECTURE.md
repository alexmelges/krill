# Krill Architecture

## Vision
Krill is a typed, local-first workflow runtime for coding-agent operations. The core goal is to make agent execution predictable, inspectable, and safe by default.

Krill prioritizes:
- deterministic behavior from declared workflows
- strong data modeling for compile-time correctness
- local execution and auditability over opaque remote orchestration

## Non-Goals
Krill is intentionally not:
- a cloud orchestration platform
- a distributed scheduler
- a replacement for full CI/CD systems
- a sandbox or policy engine for untrusted code execution

## Domain Model
Krill's runtime is centered around five core types.

### `Workflow`
A versioned plan containing a name and ordered list of `Step` values.

Core fields:
- `workflowName`
- `workflowVersion`
- `workflowSteps`

### `Step`
A single deterministic unit of execution.

Current variants:
- `exec`: run a shell command
- `echo`: print text
- `approve`: require an explicit approval decision
- `http`: make an HTTP request (method, url, headers, body)
- `env`: validate required environment variables

### `HttpStep`
HTTP request configuration for `http` step type.

Fields:
- `httpMethod`: HTTP method (GET, POST, PUT, DELETE, etc.)
- `httpUrl`: Target URL
- `httpHeaders`: Optional headers as key-value pairs
- `httpBody`: Optional request body

### `ApprovalGate`
Typed representation of a required human-or-policy decision boundary.

Current fields:
- `approvalMessage`

Future direction:
- policy id / approver identity / timeout / scope metadata

### `RunState`
Current state of one workflow run, including run id, status, step cursor, and timing.

Core fields:
- `runId`
- `runWorkflowName`
- `runStatus`
- `runCurrentStep`
- `runStartedAt`
- `runFinishedAt`

### `RunLog`
Append-only event entry for execution telemetry and audit trails, persisted as JSONL.

Core fields:
- timestamp
- run id
- workflow name
- step index/name
- event name
- event message
- optional status

## Execution Model
Krill executes workflow steps in strict sequence and never reorders or parallelizes within a run.

Deterministic sequencing guarantees:
- steps execute in declared order
- step `n+1` does not run if step `n` fails
- state transitions are linear and explicit (`pending -> running -> succeeded/failed`)
- logs are emitted in execution order as line-delimited JSON

This model keeps outcomes reproducible and easy to reason about during incident review.

## Variable Interpolation
Krill supports environment variable interpolation in step fields using `${VAR_NAME}` syntax.

Supported fields:
- `echo.text`: Interpolates variables in text output
- `exec.command`: Interpolates variables in shell commands
- `http.url`: Interpolates variables in URLs
- `http.body`: Interpolates variables in request bodies

If a variable is not set, it is replaced with an empty string.

## Safety Model
Krill enforces approval boundaries at runtime via `approve` steps.

Safety principles:
- approval gates are explicit workflow steps
- in non-interactive mode, approval fails closed unless `--auto-approve` is set
- interactive mode prompts when TTY is available
- every approval outcome is logged

Design intent for future milestones:
- require approval gates before any external send operation (network/API/tool dispatch)
- encode trust boundaries in types to prevent accidental bypass

## Roadmap

### M0: Project Foundation
- repository shape, docs, and baseline type model
- runnable CLI scaffold
- test harness setup

### M1: Local Deterministic Runtime
- parse workflow files from YAML/JSON
- execute `echo`, `exec`, and `approve`
- persist structured JSONL run logs locally

### M2: Validation and Policy Layer
- richer schema validation and static checks
- approval policy primitives
- safer defaults for high-risk step categories

### M3: Extensible Operations
- plugin-like step interfaces
- typed adapters for coding-agent operations
- stronger execution context and artifact handling

### M4: Reproducibility and Distribution Readiness
- replay/export/import of runs
- deterministic snapshots
- packaging and compatibility guarantees for OSS adoption

## Why Haskell
Krill uses Haskell because correctness pressure is high for agent orchestration.

Type-system benefits:
- explicit domain states reduce impossible runtime states
- algebraic data types model step variants clearly
- compiler-guided refactors make runtime evolution safer

Parser guarantees:
- Aeson/YAML decoding maps external workflow documents into typed structures
- parse failures are explicit and fail fast
- validation logic remains centralized and testable

The result is a runtime where behavior is legible in code and constrained by types.
