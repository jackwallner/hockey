# Project documentation

Developer notes for this repository. The published site remains in the docs directory.

## Architecture

- [HOCKEY_CONTRACT.md](architecture/HOCKEY_CONTRACT.md): NHL data contract shared by the backend and the iOS app (sources, schema, metric catalog, Swift mapping)

## Audits

- [state-machines-2026-11-06.md](audits/state-machines-2026-11-06.md): state machine audit (entitlement, purchase, season lock, data load, recent form, games, review prompt), 4 bugs with a repro suite in [state-machines-2026-11-06-repro.swift](audits/state-machines-2026-11-06-repro.swift)
- [state-machines-2026-11-06-review.md](audits/state-machines-2026-11-06-review.md): independent review of that audit, B2 confirmed, B3 and B4 minor, B1 not a bug, with hosted-view live score tests
- [state-machines-2026-11-06-fixes.md](audits/state-machines-2026-11-06-fixes.md): fixes for that review, B2, B3 and B4 fixed with regression tests, nothing held or skipped
- [state-machines-2026-11-06-verify.md](audits/state-machines-2026-11-06-verify.md): independent verification of those fixes, PASS, with revert proof and full suite runs
- [presubmit-review-2026-11-07.md](audits/presubmit-review-2026-11-07.md): pre-submit review of 1.0.3 (build 17) against live 1.0.2 (build 16), no P0 or P1, nothing fixed
- [presubmit-review-2026-11-08-deep.md](audits/presubmit-review-2026-11-08-deep.md): pre-submit deep review of 1.0.3, no P0, 3 P1 and 1 P2 fixed, 5 P2 risks open
- [2026-11-20-bug-ux.html](audits/2026-11-20-bug-ux.html): Bug and UX catalog, 2026-11-20: 10 bugs (3 medium, 7 low; 9 confirmed), 19 UX items, October audit items rechecked. Catalog only, nothing fixed.
- [2026-11-20-bug-fixes.md](audits/2026-11-20-bug-fixes.md): independent review of the fixes for that catalog: all 10 bugs verified with fail-without-fix proof, unit suite green, 5 pre-existing UI failures proven on base
- [2026-11-21-android-bug-port.md](audits/2026-11-21-android-bug-port.md): Android port of the 2026-11-20 fixes: 8 ported, 1 already fine, 1 not applicable
- [rollout-2026-11-24.md](audits/rollout-2026-11-24.md): port of the star prompt at a good moment and the remote config `trial_cta` reader, both done

## Marketing

(ASO plan lands here once keyword research is done.)
