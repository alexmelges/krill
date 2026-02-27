# Contributing to Krill

## Prerequisites

- GHC ≥ 9.14 (install via [ghcup](https://www.haskell.org/ghcup/))
- cabal ≥ 3.0

## Build

```bash
cabal build
```

## Test

```bash
cabal test
```

## Run locally

```bash
cabal run krill -- run --file examples/basic.krill.yaml --auto-approve
```

## Submitting changes

1. Fork the repo and create a branch from `main`
2. Make your changes — one logical change per PR
3. Make sure `cabal build` and `cabal test` pass
4. Open a PR against `main`

Keep PRs focused. If you're adding a new step kind, that's one PR. If you're fixing a bug in the runner, that's a separate PR.

## Code style

- Follow existing patterns in `src/Krill/`
- `-Wall -Wcompat` must pass with no warnings
- Use `GHC2021` language edition

## Adding a new step kind

1. Add a constructor to `Step` in `src/Krill/Types.hs`
2. Add parsing logic in `src/Krill/Parse.hs`
3. Add execution logic in `src/Krill/Run.hs`
4. Add tests in `test/ParseSpec.hs` and `test/RunSpec.hs`
5. Add an example in `examples/`
6. Document it in `README.md` under "Step kinds"

## Questions?

Open an issue. No question is too small.
