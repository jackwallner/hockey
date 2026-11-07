# Project documentation

Developer notes for this repository. The published site remains in the docs directory.

## Architecture

- [HOCKEY_CONTRACT.md](architecture/HOCKEY_CONTRACT.md): NHL data contract shared by the backend and the iOS app (sources, schema, metric catalog, Swift mapping)

## Audits

- [state-machines-2026-11-06.md](audits/state-machines-2026-11-06.md): state machine audit (entitlement, purchase, season lock, data load, recent form, games, review prompt), 4 bugs with a repro suite in [state-machines-2026-11-06-repro.swift](audits/state-machines-2026-11-06-repro.swift)
- [state-machines-2026-11-06-review.md](audits/state-machines-2026-11-06-review.md): independent review of that audit, B2 confirmed, B3 and B4 minor, B1 not a bug, with hosted-view live score tests
- [state-machines-2026-11-06-fixes.md](audits/state-machines-2026-11-06-fixes.md): fixes for that review, B2, B3 and B4 fixed with regression tests, nothing held or skipped
- [state-machines-2026-11-06-verify.md](audits/state-machines-2026-11-06-verify.md): independent verification of those fixes, PASS, with revert proof and full suite runs

## Marketing

(ASO plan lands here once keyword research is done.)
