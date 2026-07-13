# Prospector Concept-Group Expansion (Pass A) — Design

Date: 2026-07-13
Branch: `feat/prospector-concept-groups-passA`
Status: design approved; implementing.

## Problem

The Slope Prospector's concept-coherence analysis and all narrative signatures
operate only on variables assigned to a concept group in
`src/scripts/concept_groups.yml`. On ABS, only **102 of 338** analyzed
variables (30%) are grouped — the other 236 are invisible to the tool. Several
large, coherent, theoretically-loaded batteries sit ungrouped.

## Goal

Add coverage-verified concept groups (and rider signatures that ride on them)
so the tool sees more of the data and surfaces new cases — without touching the
matching engine.

## Non-goals

- No engine/DSL changes (that is Pass B). Pass A is data-only:
  `concept_groups.yml` + `signatures.yml` + tests.
- No cross-survey concept-group tuning (ABS-authored, per the standing non-goal).
- The W6-only batteries are explicitly deferred (see below).

## Coverage reality (verified against `abs_all_means.csv`)

A slope needs ≥3 waves. Most theoretically-interesting new batteries are **Wave-6
only** (single wave) and cannot yield slopes yet: `democrit_*`, `emergency_*` /
`emergency_powers_*`, `covid_restrict_*` / `covid_impact_*`, redistribution
(`econ_state_ownership`, `econ_govt_reduce_inequality`), most `intl_china_*` /
`intl_usa_*`, and 4 of 8 `auth_*`. These are **deferred** — added the moment a
W7 gives them time depth — and recorded as a commented block in
`concept_groups.yml` so they are not silently forgotten.

## New concept groups (7, all members ≥3 waves in ≥15 countries)

| group | members |
|---|---|
| `illiberal_values` | `auth_govt_censor_ideas`, `auth_judges_defer_executive`, `govt_should_censor_ideas`, `upright_leader_discretion` |
| `anti_pluralism` | `antiplu_diversity_chaotic`, `antiplu_groups_disrupt_harmony` |
| `system_support` | `system_capable`, `system_prefer`, `system_proud`, `system_deserves_support` |
| `traditional_authority` | `trad_obey_parents`, `trad_hierarchical_obedience`, `trad_teacher_authority`, `trad_religious_authorities`, `trad_defer_coworkers`, `trad_motherinlaw_obey` |
| `gender_traditionalism` | `trad_women_politics`, `trad_son_preference` |
| `economic_nationalism` | `glob_cultural_defense`, `glob_trade_protection`, `glob_immigration_policy` |
| `social_mobility` | `self_staircase`, `parents_staircase`, `children_staircase`, `econ_generation_opportunity` |

## New rider signatures (7, current DSL only)

```yaml
illiberal_drift:
  required:   { illiberal_values: RISING }
  supporting: { democracy_support_normative: [FALLING, FLAT] }
anti_pluralist_turn:
  required:   { anti_pluralism: RISING }
  supporting: { authoritarian_support: [RISING, FLAT] }
system_support_erosion:
  required:   { system_support: FALLING }
  supporting: { democratic_satisfaction: [FALLING, FLAT] }
value_modernization:
  required:   { traditional_authority: FALLING }
  supporting: { gender_traditionalism: [FALLING, FLAT] }
economic_nationalist_turn:
  required:   { economic_nationalism: RISING }
mobility_pessimism:
  required:   { social_mobility: FALLING }
illiberal_modernization_paradox:
  required:   { traditional_authority: FALLING, illiberal_values: RISING }
```

## Validation (built into the build — the key safety step)

Group membership is inferred from variable names; whether each battery is a
coherent same-direction construct is a hypothesis. After adding the groups,
re-run the ABS prospector and inspect `slope_groups.csv`:

- For each of the 7 new groups, record `coherence_flag`
  (`COHERENT_RISING`/`COHERENT_FALLING`/`DIVERGENT`) and `coherence_score`.
- A group that comes back **`DIVERGENT` in most countries** means its members
  pull opposite ways — its `group_direction` mean is then misleading, and it is
  flagged for **split-or-fix** before shipping, not shipped as-is.
- Record which of the 7 new signatures fire on ABS, and on which countries.

## Testing

- Synthetic **firing + negative-control tests** for each of the 7 new
  signatures in `test_signature_match.R` (proves each YAML clause is
  well-formed and can fire), mirroring the existing Phase-2 firing tests.
- The committed **behavior-lock stays green** — new groups/signatures are
  purely additive, so the 8 original signatures' frozen ABS matches are
  unchanged.

## Rollout

1. Add the 7 groups (+ deferred-block comment) to `concept_groups.yml`; re-run
   ABS; inspect coherence; split/fix any `DIVERGENT` group.
2. Add the 7 rider signatures + firing tests; re-run ABS; record fires;
   behavior-lock green.

## Risk

- **Mis-grouped (DIVERGENT) battery** → caught by the mandatory coherence
  inspection before ship.
- **Backwards signature** → the synthetic firing tests assert the intended
  direction; the coherence inspection confirms the group's real direction on
  ABS.
