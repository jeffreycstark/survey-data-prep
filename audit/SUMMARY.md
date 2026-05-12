# Audit summary — 2026-05-12 15:39:37 +07

git_commit: `b122819`  git_dirty: **true**

Mode: `--quick` (G1, F4 skipped)
Runtime: 116.4 s

## Per-survey status

| Survey | L1 schema | L3 invariants | L2 codebook | L4 anchors | L4 strict | L5 drift | L6 determ | L6 input |
|--------|-----------|---------------|-------------|------------|-----------|----------|-----------|----------|
| abs | OK 28/28 | FAIL err=27 warn=130 | skip --quick | FAIL 3 constructs, 114 sign-disagreements, 435 weak | OK 512 ok, 0 fail, 0 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| wvs | OK 14/14 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 219 skip | skip --quick | skip no manifest | skip no manifest |
| lbs | OK 9/9 | FAIL err=8 warn=2 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 334 skip | skip --quick | skip no manifest | skip no manifest |
| afro | OK 14/14 | FAIL err=45 warn=24 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 24 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| arab-barometer | OK 9/9 | FAIL err=12 warn=28 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 78 skip | skip --quick | skip no manifest | skip no manifest |
| kamos | OK 6/6 | FAIL err=5 warn=2 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 8 skip | skip --quick | skip no manifest | skip no manifest |
| kgss | OK 18/18 | OK err=0 warn=64 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 790 skip | skip --quick | skip no manifest | skip no manifest |
| kipa-corruption | OK 4/4 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 3 skip | skip --quick | skip no manifest | skip no manifest |
| kinu | OK 8/8 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 43 skip | skip --quick | skip no manifest | skip no manifest |
| ipus | OK 3/3 | FAIL err=7 warn=0 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 87 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |

## Top audit findings

1. **[abs]** L4 anchors — democratic_attitudes/dem_best_form/w4: expected=positive observed=negative  
   See `audit/reports/abs/`
2. **[abs]** L4 anchors — democratic_attitudes/dem_best_form/w5: expected=positive observed=negative  
   See `audit/reports/abs/`
3. **[abs]** L4 anchors — democratic_attitudes/democracy_suitability/w5: expected=positive observed=negative  
   See `audit/reports/abs/`
4. **[afro]** L3 invariants — dem_support_preferable/w1/coverage: 5.6% coverage loss (1205 of 21378 values)  
   See `audit/reports/afro/`
5. **[afro]** L3 invariants — urban_rural/w5/coverage: 1.3% coverage loss (687 of 51587 values)  
   See `audit/reports/afro/`
6. **[afro]** L3 invariants — urban_rural/w6/coverage: 1.1% coverage loss (600 of 53935 values)  
   See `audit/reports/afro/`
7. **[abs]** L3 invariants — trust_ngos/w6/coverage: 1.6% coverage loss (151 of 9289 values)  
   See `audit/reports/abs/`
8. **[abs]** L3 invariants — trust_television/w6/coverage: 1.6% coverage loss (151 of 9289 values)  
   See `audit/reports/abs/`
9. **[abs]** L3 invariants — election_free_fair/w6/coverage: 1.4% coverage loss (198 of 13797 values)  
   See `audit/reports/abs/`
10. **[arab-barometer]** L3 invariants — gender/w5/coverage: 3.8% coverage loss (1070 of 27818 values)  
   See `audit/reports/arab-barometer/`

## Cross-cutting

- Recoding registry: OK
- JEFF_MUST_INVESTIGATE.md: 4 open findings (high+medium priority)

## Skipped modules (prerequisites missing)

- **wvs**: L3 invariants (needs harmonization rerun); L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 219 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **lbs**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 334 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **afro**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 24 skip)
- **arab-barometer**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 78 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kamos**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 8 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kgss**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 790 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kipa-corruption**: L3 invariants (needs harmonization rerun); L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 3 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kinu**: L3 invariants (needs harmonization rerun); L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 43 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **ipus**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 87 skip)

---
Generated by `src/r/audit/run_all.R` at 2026-05-12 15:39:37 +07.
