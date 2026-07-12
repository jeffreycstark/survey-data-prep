# Slope Prospector — Signature Extension Design

Date: 2026-07-12
Branch: `feat/prospector-signature-extension`
Status: design (awaiting user review before implementation planning)

## Problem

The Slope Prospector matches countries against named theoretical signatures
(`NARRATIVE_PATTERNS` in `src/scripts/slope_prospector.R`). Two limits cap how
much "interesting stuff" it can surface:

1. **Thin vocabulary.** The matcher sees only `group_direction ∈ {RISING,
   FALLING, FLAT}` — a 3-state, mean-slope summary per country × concept group.
   Everything else the pipeline already computes is written to CSV and then
   ignored by matching: structural-break presence (`structural_breaks.csv`),
   rose-then-fell reversals and acceleration (`acceleration.csv`), within-group
   incoherence (`coherence_flag = MIXED`), `sd_slope`, and — critically — the
   **endpoint level** (a group can be RISING off a low base or RISING to a
   majority; the matcher cannot tell these apart).

2. **Small catalog.** Only 8 signatures are defined, several theoretically
   important patterns are unexpressed even within the current 3-state DSL, and
   the machinery lives inline in a ~900-line monolith with **zero tests**.

## Goals

- Add a library of new theoretical signatures.
- Extend the matcher's vocabulary with richer primitives: **level + magnitude**,
  **shape** (reversal / acceleration), **break-timing + true sequences**, and
  **within-group splits**.
- Do both without breaking the 8 existing signatures, and with test coverage
  for a currently-untested component.

## Non-goals

- No changes to slope estimation, normalization, clustering, dashboards, or any
  prospector stage other than signature detection (section 10) and the feature
  inputs it needs.
- No per-survey concept-group tuning. `concept_groups.yml` is ABS-oriented and
  matches Afro/LBS only where variable names coincide; fixing that is separate
  future work. Signatures are authored against the existing concept groups.
- No new narrative-pattern *rendering* beyond the existing
  `narrative_patterns.csv` + report section (extra columns are additive).

## Approach

**Declarative condition-objects, backward-compatible, backed by a precomputed
feature frame, with the signature registry externalized to YAML** (chosen over
predicate-function closures — which turn signatures into unreadable code — and
over a minimal in-monolith bolt-on — which leaves the matcher untested and the
monolith growing).

A signature slot value stays a plain string or character vector for the simple
case, and may also be a condition list. A bare `"FALLING"` normalizes to
`list(dir = "FALLING")`, so **every current signature parses unchanged**.

## Architecture

Extract signature machinery out of the monolith into a small, tested unit. Only
the signature-detection concern moves; the rest of `slope_prospector.R` is left
alone.

```
src/scripts/prospector/
  signature_features.R   # slopes + acceleration + breaks → country×group feature frame
  signature_match.R      # condition evaluator + registry loader
  signatures.yml         # signature registry (DATA, not code)
  test_signature_match.R # fault-injection tests
src/scripts/slope_prospector.R   # section 10 shrinks to source() + one call
```

### Unit 1 — `signature_features.R`

**What it does:** given the per-country×variable `slopes` frame plus the
acceleration and break tables, emits one enriched row per **country × concept
group**.

**Interface:** `build_group_features(slopes, acceleration, breaks, concept_groups,
final_values, thresholds) -> tibble`.

**Feature-frame columns:**

| column | derivation |
|---|---|
| `group_direction` (RISING/FALLING/FLAT) | existing: `mean_slope` vs `FLAT_THRESHOLD` |
| `magnitude_tier` (SLOW/FAST) | `abs(mean_slope)` vs `FAST_THRESHOLD` |
| `shape` (STEADY / REVERSED_UP / REVERSED_DOWN / ACCELERATING / DECELERATING) | aggregate member rows of `acceleration.csv`; group verdict requires a quorum of members agreeing (`SHAPE_QUORUM`) |
| `ends_level` (LOW/MID/HIGH) | mean of members' **final-wave normalized [0,1]** value vs `ENDS_LOW`/`ENDS_HIGH` cutoffs |
| `broke_at_wave` (int or NA) | modal member break wave from `breakpoints()` (see Break-detector upgrade) |

**Depends on:** the normalized member values (final wave) and the augmented
break table. Also passes through the raw variable-level `slopes` frame for
`within`-group evaluation.

### Unit 2 — `signature_match.R`

**What it does:** loads `signatures.yml`, evaluates each signature against the
feature frame (and, for `within`, the variable-level slopes), returns the
`narrative_patterns` tibble.

**Interface:** `load_signatures(path) -> list`; `match_signatures(features,
var_slopes) -> tibble(country, pattern_id, label, description)`.

**Condition types (the evaluator dispatches on shape of the slot value):**

- **simple** — `list(dir=, magnitude=, shape=, level=)`, evaluated as a
  conjunction against the feature-frame row. Bare string/vector →
  `list(dir = <that>)`. Absent sub-keys are ignored.
- **within** — `within: {group: {var1: DIR, var2: DIR}}`, evaluated against
  variable-level slopes filtered to that group's members. Fires only if **all**
  named sub-variables match.
- **ordered** — `ordered: [{group:A, rel:FALLS_BEFORE}, {group:B,
  rel:RISES_AFTER}]`, evaluated by comparing `broke_at_wave` across the named
  groups. NA break wave ⇒ condition fails (cannot order an unbroken series).

`required` / `supporting` semantics are preserved: all `required` must hold; a
`supporting` slot holds if the group is absent or matches. `level`, `within`,
and `ordered` are additional top-level keys evaluated as `required`.

### Break-detector upgrade

`structural_breaks.csv` currently records only a supF statistic + p-value, not
the break location. Add `strucchange::breakpoints(mean_value ~ wave_num)` to
estimate the breakpoint wave per country × variable, keeping the existing supF
p-value as the significance gate. `strucchange` is already installed (confirmed
in `renv`). Emit a new `break_wave` column; leave existing columns intact.

## Signature catalog

### Phase 1 — current engine, no new primitives (six)

| id | required / supporting | theory |
|---|---|---|
| `authoritarian_drift` | req: `democracy_support_normative`=FALLING **+** `authoritarian_support`=RISING | demand-side erosion |
| `diffuse_specific_decoupling` | req: `democratic_satisfaction`=FALLING; sup: `democracy_support_normative`={RISING,FLAT} | Easton diffuse/specific; Norris critical citizens |
| `rule_of_law_erosion` | req: `rule_of_law`=FALLING; sup: `accountability_perceptions`={FALLING,FLAT} | erosion of liberal substance |
| `alienation_withdrawal` | req: `political_efficacy`=FALLING **+** `political_action_contacting_protest`=FALLING | efficacy → disengagement |
| `output_trust_legitimation` | req: `economic_present`=RISING **+** `institutional_trust_executive`=RISING; sup: `democracy_assessment_empirical`={FALLING,FLAT} | performance legitimacy via trust |
| `accountable_dissatisfaction` | req: `democratic_satisfaction`=FALLING **+** `institutional_trust_executive`=FALLING; sup: `democracy_support_normative`={RISING,FLAT} | **health** signal: accountability working |

All map to existing concept groups; no new concept groups required.

### Phase 2 — uses new primitives (six, incl. upgrades)

```yaml
coup_honeymoon:               # SHAPE
  required: { authoritarian_support: { shape: REVERSED_UP } }
authoritarian_ascendant:      # LEVEL
  required: { authoritarian_support: { dir: RISING, level: ENDS_HIGH } }
accelerating_trust_collapse:  # MAGNITUDE + LEVEL
  required:
    institutional_trust_executive:    { dir: FALLING, magnitude: FAST }
    institutional_trust_intermediary: FALLING
  level: { institutional_trust_executive: ENDS_LOW }
true_demobilization_sequence: # TIMING
  ordered:
    - { group: political_action_contacting_protest, rel: FALLS_BEFORE }
    - { group: authoritarian_support,               rel: RISES_AFTER }
selective_accountability:     # WITHIN
  within:
    accountability_perceptions: { gov_elections_real_choice: RISING, gov_courts_powerless: RISING }
efficacy_trap:                # WITHIN
  within:
    political_efficacy: { efficacy_ability_participate: RISING, efficacy_no_influence: RISING }
```

Each has a known real candidate (acceptance targets): Thailand →
`coup_honeymoon`; Eswatini → `accelerating_trust_collapse`.

## Tunable globals (documented beside `FLAT_THRESHOLD`)

- `FAST_THRESHOLD` — `abs(mean_slope)` above which `magnitude_tier = FAST`.
- `ENDS_LOW`, `ENDS_HIGH` — cutoffs on normalized [0,1] final level.
- `SHAPE_QUORUM` — min share of group members agreeing for a group shape verdict.

## Testing

New `src/scripts/prospector/test_signature_match.R`, mirroring
`src/r/audit/test_*.R`:

1. **Behavior-lock:** new engine on `abs_all_means.csv` reproduces the 8 existing
   signatures' matches identically (extraction is behavior-preserving).
2. **Backward-compat:** `"FALLING"` and `list(dir="FALLING")` yield identical
   verdicts.
3. **Per-primitive units** on synthetic feature frames: `level` at ENDS
   boundary; `magnitude` at `FAST_THRESHOLD`; `shape` REVERSED_UP from
   (early≤0, late>0); `ordered` FALLS_BEFORE when break waves order correctly
   and NA-safe; `within` requires all sub-variables.
4. **Break-detector:** `breakpoints()` returns the planted wave on a synthetic
   stable-then-broke series.
5. **Acceptance:** each new signature fires on its intended real case and not on
   a negative control.

## Rollout

1. Phase 0 — extract machinery to the new unit, externalize the 8 signatures to
   `signatures.yml`, add behavior-lock test. **No behavior change.**
2. Phase 1 — add the six current-engine signatures + tests.
3. Phase 2 — break-detector upgrade → feature frame enrichment → new primitives
   in the evaluator → the six Phase-2 signatures + tests.

Each phase is independently shippable and leaves the prospector runnable.

## Risks

- **Refactor regression** — mitigated by the behavior-lock test gating Phase 0.
- **Threshold sensitivity** — new cutoffs (`FAST_THRESHOLD`, `ENDS_*`) are
  eyeballed; exposed as globals and documented so they can be tuned per run.
- **Break-wave noise** on 6-point series — `breakpoints()` on short series is
  imprecise; `ordered` conditions are gated on the existing supF p-value and
  treat NA as non-firing, so noise suppresses rather than fabricates matches.
- **Cross-survey portability** — signatures are ABS-tuned via the concept
  groups; firing on Afro/LBS is opportunistic (name overlap only). Documented as
  a non-goal.
