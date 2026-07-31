# Audit summary — 2026-07-31 17:15:33 +07

git_commit: `d35ce1e`  git_dirty: **true**

Mode: `--quick` (G1, F4 skipped)
Runtime: 376.0 s

## Per-survey status

| Survey | L1 schema | L3 invariants | L3 oob | L2 codebook | L4 anchors | L4 strict | L4 labels | L4 battery | L4 coverage | L4 binwidth | L5 drift | L6 determ | L6 input |
|--------|-----------|---------------|--------|-------------|------------|-----------|-----------|------------|-------------|-------------|----------|-----------|----------|
| abs | OK 28/28 | FAIL err=3 warn=88 | warn 0 err, 15 warn | skip --quick | FAIL 5 constructs, 7 sign-disagreements, 719 weak (+107 ack) | OK 577 ok, 0 fail, 0 skip | FAIL 322 ok, 18 err, 793 skip | warn 557 ok, 101 hint, 110 weak | warn 44 cov, 16 ex, 207 unc | FAIL 1034 ok, 56 err, 2 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| wvs | OK 15/15 | FAIL err=8 warn=2 | warn 0 err, 4 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 219 skip | OK 179 ok, 0 err, 202 skip | warn 194 ok, 15 hint, 19 weak | warn 8 cov, 7 ex, 59 unc | FAIL 373 ok, 1 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| lbs | OK 10/10 | OK err=0 warn=19 | warn 0 err, 2 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 341 skip | OK 271 ok, 0 err, 266 skip | warn 224 ok, 10 hint, 2 weak | warn 9 cov, 3 ex, 13 unc | OK 511 ok, 0 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| afro | OK 21/21 | FAIL err=4 warn=23 | warn 0 err, 15 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 36 skip | OK 160 ok, 0 err, 224 skip | warn 153 ok, 9 hint, 0 weak | warn 9 cov, 9 ex, 37 unc | FAIL 320 ok, 1 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| arab-barometer | OK 9/9 | OK err=0 warn=24 | warn 0 err, 5 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 78 skip | OK 39 ok, 0 err, 150 skip | warn 72 ok, 10 hint, 15 weak | warn 9 cov, 8 ex, 22 unc | FAIL 142 ok, 3 err, 2 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| kamos | OK 6/6 | OK err=0 warn=6 | OK 0 err, 0 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 8 skip | OK 4 ok, 0 err, 139 skip | warn 30 ok, 6 hint, 0 weak | warn 1 cov, 6 ex, 24 unc | OK 108 ok, 0 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| kgss | OK 18/18 | OK err=0 warn=182 | OK 0 err, 0 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 790 skip | OK 548 ok, 0 err, 826 skip | warn 693 ok, 39 hint, 148 weak | warn 5 cov, 6 ex, 161 unc | OK 1223 ok, 0 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| kipa-corruption | OK 4/4 | OK err=0 warn=77 | OK 0 err, 0 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 3 skip | OK 13 ok, 0 err, 579 skip | warn 405 ok, 16 hint, 0 weak | warn 0 cov, 3 ex, 31 unc | warn 589 ok, 0 err, 3 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| kinu | OK 8/8 | OK err=0 warn=228 | warn 0 err, 37 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 43 skip | OK 502 ok, 0 err, 820 skip | warn 507 ok, 57 hint, 202 weak | warn 1 cov, 9 ex, 109 unc | OK 1322 ok, 0 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| ipus | OK 3/3 | OK err=0 warn=0 | OK 0 err, 0 warn | skip --quick | skip no applicable anchors (anchor var absent) | skip 0 ok, 0 fail, 86 skip | OK 48 ok, 0 err, 144 skip | warn 25 ok, 6 hint, 14 weak | warn 0 cov, 2 ex, 4 unc | FAIL 191 ok, 1 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |
| gcb | OK 4/4 | OK err=0 warn=1 | OK 0 err, 0 warn | skip --quick | skip no applicable anchors (anchor var absent) | OK 0 ok, 0 fail, 0 skip | OK 7 ok, 0 err, 15 skip | OK 6 ok, 0 hint, 0 weak | warn 0 cov, 7 ex, 11 unc | OK 18 ok, 0 err, 0 warn | skip --quick | skip no manifest | skip no manifest |
| klosa | OK 8/8 | OK err=0 warn=9 | warn 0 err, 1 warn | skip --quick | skip no applicable anchors (anchor var absent) | OK 0 ok, 0 fail, 0 skip | skip 0 ok, 0 err, 1 skip | warn 27 ok, 12 hint, 67 weak | warn 0 cov, 10 ex, 15 unc | OK 156 ok, 0 err, 0 warn | skip --quick | OK all paths match | OK all inputs unchanged |

## Top audit findings

1. **[abs]** L4 binwidth — community_leader_contact/w5: bin signature 3:2|2:1|1:2 diverges from sibling waves  
   See `audit/reports/abs/`
2. **[abs]** L4 binwidth — community_leader_contact/w6: bin signature 3:2|2:1|1:2 diverges from sibling waves  
   See `audit/reports/abs/`
3. **[abs]** L4 binwidth — corrupt_local_govt/w6: bin signature 4:1|3:1|2:1|1:2 diverges from sibling waves  
   See `audit/reports/abs/`
4. **[abs]** L4 labels — demo_political_equality/w1/safe_reverse_4pt: raw pos@high but declared pos@high  
   See `audit/reports/abs/`
5. **[abs]** L4 labels — econ_family_income_fair_6pt/w4/identity: raw pos@low but declared pos@high  
   See `audit/reports/abs/`
6. **[abs]** L4 labels — govt_should_censor_ideas/w1/safe_reverse_4pt: raw pos@low but declared pos@low  
   See `audit/reports/abs/`
7. **[wvs]** L3 invariants — corrupt_national_govt/w6/transformation: scale conversion (|ρ| ≈ 1) FAILED: r=0.950, ρ=0.930 (expected >0.99)  
   See `audit/reports/wvs/`
8. **[wvs]** L3 invariants — corrupt_national_govt/w7/transformation: scale conversion (|ρ| ≈ 1) FAILED: r=0.950, ρ=0.912 (expected >0.99)  
   See `audit/reports/wvs/`
9. **[wvs]** L3 invariants — urban_rural/w5/coverage: 1.4% coverage loss (156 of 11383 values)  
   See `audit/reports/wvs/`
10. **[abs]** L4 anchors — economic_evaluations/econ_outlook_1yr/w1: expected=positive observed=negative  
   See `audit/reports/abs/`

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
- JEFF_MUST_INVESTIGATE.md: 6 open findings (high+medium priority)

## Skipped modules (prerequisites missing)

- **wvs**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 219 skip)
- **lbs**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 341 skip)
- **afro**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 36 skip)
- **arab-barometer**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 78 skip)
- **kamos**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 8 skip)
- **kgss**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 790 skip)
- **kipa-corruption**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 3 skip)
- **kinu**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 43 skip)
- **ipus**: L4 anchors (no applicable anchors (anchor var absent)); L4 strict (0 ok, 0 fail, 86 skip)
- **gcb**: L4 anchors (no applicable anchors (anchor var absent)); L6 determinism (no manifest); L6 input drift (no manifest)
- **klosa**: L4 anchors (no applicable anchors (anchor var absent)); L4 labels (0 ok, 0 err, 1 skip)

---
Generated by `src/r/audit/run_all.R` at 2026-07-31 17:15:33 +07.
