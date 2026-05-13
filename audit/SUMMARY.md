# Audit summary — 2026-05-13 15:42:57 +07

git_commit: `355e2ca`  git_dirty: **true**

Mode: `--quick` (G1, F4 skipped)
Runtime: 99.8 s

## Per-survey status

| Survey | L1 schema | L3 invariants | L2 codebook | L4 anchors | L4 strict | L5 drift | L6 determ | L6 input |
|--------|-----------|---------------|-------------|------------|-----------|----------|-----------|----------|
| abs | OK 28/28 | FAIL err=27 warn=130 | skip --quick | FAIL 3 constructs, 7 sign-disagreements, 435 weak (+107 ack) | OK 512 ok, 0 fail, 0 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| wvs | OK 14/14 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 219 skip | skip --quick | skip no manifest | skip no manifest |
| lbs | OK 9/9 | FAIL err=8 warn=2 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 334 skip | skip --quick | skip no manifest | skip no manifest |
| afro | OK 14/14 | FAIL err=45 warn=24 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 24 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| arab-barometer | OK 9/9 | FAIL err=12 warn=28 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 78 skip | skip --quick | skip no manifest | skip no manifest |
| kamos | OK 6/6 | FAIL err=5 warn=2 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 8 skip | skip --quick | skip no manifest | skip no manifest |
| kgss | OK 18/18 | OK err=0 warn=64 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 790 skip | skip --quick | skip no manifest | skip no manifest |
| kipa-corruption | OK 4/4 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 3 skip | skip --quick | skip no manifest | skip no manifest |
| kinu | OK 8/8 | OK err=0 warn=219 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 43 skip | skip --quick | OK all paths match | OK all inputs unchanged |
| ipus | OK 3/3 | FAIL err=1 warn=0 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 87 skip | skip --quick | OK all paths match | OK all inputs unchanged |

## Top audit findings

1. **[afro]** L3 invariants — dem_support_preferable/w1/coverage: 5.6% coverage loss (1205 of 21378 values)  
   See `audit/reports/afro/`
2. **[afro]** L3 invariants — urban_rural/w5/coverage: 1.3% coverage loss (687 of 51587 values)  
   See `audit/reports/afro/`
3. **[afro]** L3 invariants — urban_rural/w6/coverage: 1.1% coverage loss (600 of 53935 values)  
   See `audit/reports/afro/`
4. **[abs]** L3 invariants — trust_ngos/w6/coverage: 1.6% coverage loss (151 of 9289 values)  
   See `audit/reports/abs/`
5. **[abs]** L3 invariants — trust_television/w6/coverage: 1.6% coverage loss (151 of 9289 values)  
   See `audit/reports/abs/`
6. **[abs]** L3 invariants — election_free_fair/w6/coverage: 1.4% coverage loss (198 of 13797 values)  
   See `audit/reports/abs/`
7. **[arab-barometer]** L3 invariants — gender/w5/coverage: 3.8% coverage loss (1070 of 27818 values)  
   See `audit/reports/arab-barometer/`
8. **[arab-barometer]** L3 invariants — age/w7/coverage: 1.9% coverage loss (502 of 26148 values)  
   See `audit/reports/arab-barometer/`
9. **[arab-barometer]** L3 invariants — age/w8/coverage: 1.4% coverage loss (214 of 15596 values)  
   See `audit/reports/arab-barometer/`
10. **[lbs]** L3 invariants — corruption_experience/y2013/coverage: 81.1% coverage loss (15571 of 19195 values)  
   See `audit/reports/lbs/`

## Acknowledged findings (documented measurement-validity)

Anchor-diagnostic rows the anchor YAMLs flag as documented findings
(not coding bugs) via `acknowledged_disagreements:`. Counted as
`ok_acknowledged` rather than fails. Group: variable × reason.

- **dem_best_form** (abs, 2 rows): waves=w4,w5; countries=2  
  Reason: Hong Kong post-Umbrella / anti-extradition political contestation: pro-democracy respondents are dissatisfied with HK reality while pro-Beijing respondents are satisfied with HK's 'democracy' as the regime defines it. 96%+ of dem_best_form country × wave combinations align with the positive sign as expected; only HK W4/W5 inverts.

- **democracy_suitability** (abs, 1 row): waves=w5; countries=2  
  Reason: Same HK political-contestation pattern as dem_best_form (W4 + W5); democracy_suitability specifically inverts in HK W5 (2018-19, the anti-extradition period). Genuine local political effect, not a harmonization error.
- **strongman_rule** (abs, 19 rows): waves=w1,w2,w3,w4,w5,w6; countries=10,11,12,13,14,18,2,3,4,6,8  
  Reason: Same regime-conformity pattern, somewhat attenuated relative to single_party_rule and military_rule (W6 starts showing the theoretical negative direction in some democracies). Documented; see the top-level notes block.

- **single_party_rule** (abs, 43 rows): waves=w1,w2,w3,w4,w5,w6; countries=<pooled>,10,11,12,13,14,18,2,3,4,5,6,7,8,9  
  Reason: Regime-conformity + hybrid-regime + young-democracy variation. Theory's negative correlation between single-party-rule endorsement and democratic satisfaction holds only in mature liberal democracies (Japan=1, Australia=15). In the other ABS countries the relationship inverts (authoritarian states) or attenuates (hybrid / young democracies). Documented; see the top-level notes block.

- **military_rule** (abs, 42 rows): waves=w1,w2,w3,w4,w5,w6; countries=<pooled>,10,11,12,13,14,18,2,3,4,5,6,8,9  
  Reason: Same regime-conformity + hybrid-regime pattern as single_party_rule. Particularly pronounced in countries with recent military-government history (Thailand, Indonesia, Myanmar) where 'military rule' has institutional rather than purely abstract meaning.


## Cross-cutting

- Recoding registry: OK
- JEFF_MUST_INVESTIGATE.md: 5 open findings (high+medium priority)

## Skipped modules (prerequisites missing)

- **wvs**: L3 invariants (needs harmonization rerun); L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 219 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **lbs**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 334 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **afro**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 24 skip)
- **arab-barometer**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 78 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kamos**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 8 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kgss**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 790 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kipa-corruption**: L3 invariants (needs harmonization rerun); L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 3 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kinu**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 43 skip)
- **ipus**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 87 skip)

---
Generated by `src/r/audit/run_all.R` at 2026-05-13 15:42:57 +07.
