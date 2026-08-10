# Audit summary — 2026-08-10 10:58:30 +07

git_commit: `f28405c`  git_dirty: **true**

Mode: full
Runtime: 2.8 s

## Per-survey status

| Survey | L1 schema | L3 invariants | L3 oob | L2 codebook | L4 anchors | L4 strict | L4 labels | L4 battery | L4 coverage | L4 binwidth | L5 drift | L6 determ | L6 input |
|--------|-----------|---------------|--------|-------------|------------|-----------|-----------|------------|-------------|-------------|----------|-----------|----------|
| abs | OK 28/28 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| wvs | OK 16/16 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| lbs | OK 11/11 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| afro | OK 22/22 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| arab-barometer | OK 10/10 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| kamos | OK 7/7 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| kgss | OK 18/18 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| kipa_corruption | OK 5/5 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| kinu | OK 9/9 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| ipus | OK 4/4 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| gcb | OK 4/4 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| klosa | OK 8/8 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |
| cfps | OK 2/2 | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only | skip --specs-only |

## Top audit findings

_No fail rows surfaced._

## Acknowledged findings (documented measurement-validity)

_No acknowledged disagreements in this run._

## Cross-cutting

- Recoding registry: OK
- Convention collisions: 0 error, 11 exempt, 0 unparseable. Report: /Users/jeffreystark/Development/Research/survey-data-prep/audit/reports/convention_collisions.csv
- Key uniqueness: --specs-only
- JEFF_MUST_INVESTIGATE.md: 5 open findings (high+medium priority)

## Skipped modules (prerequisites missing)

- **abs**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **wvs**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **lbs**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **afro**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **arab-barometer**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **kamos**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **kgss**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **kipa_corruption**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **kinu**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **ipus**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **gcb**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **klosa**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)
- **cfps**: L3 invariants (--specs-only); L3 out-of-range (--specs-only); L2 codebook (--specs-only); L4 anchor (--specs-only); L4 strict reversal (--specs-only); L4 label recon (--specs-only); L4 battery coherence (--specs-only); L4 anchor coverage (--specs-only); L4 bin-width parity (--specs-only); L5 drift (--specs-only); L6 determinism (--specs-only); L6 input drift (--specs-only)

---
Generated by `src/r/audit/run_all.R` at 2026-08-10 10:58:30 +07.
