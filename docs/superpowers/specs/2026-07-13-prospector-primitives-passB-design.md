# Prospector Free-Primitives (Pass B) — Design

Date: 2026-07-13
Branch: `feat/prospector-primitives-passB`
Status: implemented.

## Problem

The matcher computes three signals per group/variable and discards them at match
time: `sd_slope` and `coherence_flag` (both on `group_coherence`) and the
quadratic `quad_term`/`nonlinear` (on `slopes`). Exposing them as DSL condition
keys is cheap and adds real expressiveness.

## New feature-frame columns + DSL keys

| DSL key | values | source | column |
|---|---|---|---|
| `coherence` | `COHERENT` / `DIVERGENT` | `n_rising`/`n_falling` on `group_coherence` | `coherence` |
| `volatility` | `STABLE` / `VOLATILE` | `sd_slope` vs `VOLATILE_THRESHOLD` | `volatility` |
| `curvature` | `LINEAR` / `CONVEX` (U) / `CONCAVE` (hump) | member `quad_term` sign, gated by `nonlinear`, group quorum `CURVE_QUORUM` | `curvature` |

**Design refinement made during validation:** `coherence` was *first* defined
from `group_coherence$coherence_flag` (which is `DIVERGENT` whenever members are
not strictly all-same-sign). On ABS that fired `fractured_democratic_support`
in **all 13 countries** — near-zero-slope groups trip the all-same-sign test on
sign noise. Redefined to a **genuine split**: `DIVERGENT` iff `n_rising > 0 AND
n_falling > 0` (at least one member clearly rising past `FLAT_THRESHOLD` and one
clearly falling). After the fix the signature fires in 4 countries (Vietnam,
Hong Kong, China, Mongolia) — discriminating.

## Wiring

`build_group_features` gains an optional `var_curvature` arg (the `slopes`
subset `country, variable, quad_term, nonlinear`; `NULL` ⇒ every group
`LINEAR`). `slope_prospector.R` builds it from `slopes` and passes it, and adds
two globals `VOLATILE_THRESHOLD` (0.15) and `CURVE_QUORUM` (0.5) beside the
existing tunables. `normalize_condition` and `eval_simple_condition` gain the
three keys (each an AND-conjunct like `magnitude`/`shape`/`level`, skipped when
the feature column is absent — so backward-compatible).

## Signatures (4)

```yaml
fractured_democratic_support:
  required: { democracy_support_normative: { coherence: DIVERGENT } }
volatile_institutional_trust:
  required: { institutional_trust_executive: { volatility: VOLATILE } }
democratic_recovery:
  required: { democracy_assessment_empirical: { curvature: CONVEX } }
boom_bust_economy:
  required: { economic_present: { curvature: CONCAVE } }
```

On ABS: `fractured_democratic_support` fires in 4 countries; the other three
fire in 0 (real-data thresholds not met — mechanism proven by synthetic tests,
same acceptable pattern as the illiberal Pass-A signatures).

## Testing

- Feature-frame unit tests for all three columns at their thresholds, incl. the
  `var_curvature = NULL → LINEAR` default and both curvature signs.
- Firing + negative-control tests per signature.
- Behavior-lock stays green (additive; the 8 original signatures unchanged).
- Two stale pre-Pass-B test fixtures (`thr` without `VOLATILE`/`CURVE_QUORUM`;
  `gc` without `n_rising`/`n_falling`) updated to the current column contract.

## Non-goals / notes

- `VOLATILE_THRESHOLD` and `CURVE_QUORUM` are eyeballed; exposed as globals for
  tuning. Their signatures not firing on ABS is expected, not a defect.
