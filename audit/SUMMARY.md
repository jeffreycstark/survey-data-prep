# Audit summary — 2026-05-14 20:16:12 +07

git_commit: `bf6ec3a`  git_dirty: **true**

Mode: `--quick` (G1, F4 skipped)
Runtime: 116.3 s

## Per-survey status

| Survey | L1 schema | L3 invariants | L2 codebook | L4 anchors | L4 strict | L5 drift | L6 determ | L6 input |
|--------|-----------|---------------|-------------|------------|-----------|----------|-----------|----------|
| abs | OK 28/28 | FAIL err=3 warn=89 | skip --quick | FAIL 3 constructs, 7 sign-disagreements, 444 weak (+107 ack) | OK 510 ok, 0 fail, 0 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| wvs | OK 14/14 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 219 skip | skip --quick | skip no manifest | skip no manifest |
| lbs | OK 9/9 | OK err=0 warn=19 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 334 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| afro | OK 14/14 | OK err=0 warn=25 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 24 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| arab-barometer | OK 9/9 | OK err=0 warn=25 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 78 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| kamos | OK 6/6 | OK err=0 warn=6 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 8 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| kgss | OK 18/18 | OK err=0 warn=64 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 790 skip | skip --quick | skip no manifest | skip no manifest |
| kipa-corruption | OK 4/4 | skip needs harmonization rerun | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 3 skip | skip --quick | skip no manifest | skip no manifest |
| kinu | OK 8/8 | OK err=0 warn=219 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 43 skip | skip --quick | FAIL exit=1 | OK all inputs unchanged |
| ipus | OK 3/3 | OK err=0 warn=0 | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 86 skip | skip --quick | OK all paths match | OK all inputs unchanged |

## Top audit findings

1. **[abs]** L4 anchors — economic_evaluations/econ_outlook_1yr/w1: expected=positive observed=negative  
   See `audit/reports/abs/`
2. **[abs]** L4 anchors — economic_evaluations/econ_family_outlook/w1: expected=positive observed=negative  
   See `audit/reports/abs/`
3. **[abs]** L4 anchors — economic_evaluations/gov_basic_necessities/w2: expected=positive observed=negative  
   See `audit/reports/abs/`
4. **[abs]** L3 invariants — idnumber/w6/coverage: Gained 19 values (harmonized > raw) - check logic  
   See `audit/reports/abs/`
5. **[abs]** L3 invariants — gate_contact_influential/w2/coverage: 30.0% coverage loss (4006 of 13347 values)  
   See `audit/reports/abs/`
6. **[abs]** L3 invariants — gate_contact_influential/w2/crosstab: 3 raw values map to multiple outputs  
   See `audit/reports/abs/`
7. **[abs]** L6 determinism — [drift] src/r/utils/recoding.R  (engine_versions)  
   See `audit/reports/abs/`
8. **[afro]** L6 determinism — [drift] src/r/utils/recoding.R  (engine_versions)  
   See `audit/reports/afro/`
9. **[arab-barometer]** L6 determinism — [drift] src/r/utils/recoding.R  (engine_versions)  
   See `audit/reports/arab-barometer/`
10. **[kamos]** L6 determinism — [drift] src/r/utils/recoding.R  (engine_versions)  
   See `audit/reports/kamos/`

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
- **lbs**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 334 skip)
- **afro**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 24 skip)
- **arab-barometer**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 78 skip)
- **kamos**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 8 skip)
- **kgss**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 790 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kipa-corruption**: L3 invariants (needs harmonization rerun); L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 3 skip); L6 determinism (no manifest); L6 input drift (no manifest)
- **kinu**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 43 skip)
- **ipus**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 86 skip)

---
Generated by `src/r/audit/run_all.R` at 2026-05-14 20:16:12 +07.
