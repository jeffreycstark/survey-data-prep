# Prospector Bimodality / Two-Camp Split (Pass C2) — Design

Date: 2026-07-14
Branch: `feat/prospector-bimodality-passC2`
Status: design approved (statistic = van der Eijk's *A*); implementing.

## Problem

C1a (`detect_polarization`) flags variables whose **mean is flat while within-wave
SD moves**. But a rising SD is ambiguous about *shape*: the distribution could be

- **spreading out uniformly** — mild, diffuse dissensus; or
- **splitting into two camps at the poles** — genuine polarization.

SD cannot tell these apart (a uniform distribution and a 50/50 bimodal split over
the same support can have near-identical SD). This is the missing piece that makes
C1a's signal *interpretable*. C2 measures distributional **shape** over waves.

## Approach — van der Eijk's Agreement *A*

Per country×wave×variable, compute van der Eijk's *A* (van der Eijk 2001,
"Measuring agreement in ordered rating scales," *Quality & Quantity* 35: 325–341)
on the frequency vector over the ordinal response codes:

- *A* = **+1** → all mass in one category (perfect agreement, maximally unimodal).
- *A* = **0** → responses uniform across all categories.
- *A* = **−1** → mass split 50/50 at the two extreme categories (maximal bimodal
  polarization).

The **polarization series** is `−A`. It is fed through the module's existing
`.pol_slopes()` machinery (per country×variable min-max-normalized slope over
waves, WLS by `n`), identical to how C1a slopes `sd_value`.

### Why *A* over the alternatives

| Candidate | Verdict | Reason |
|---|---|---|
| **van der Eijk *A*** | **chosen** | Purpose-built for *ordered rating scales* — exactly ABS. Handles bounded-discrete distributions natively; the −1 pole is unambiguously "two camps at the extremes." Field-standard for ordinal polarization. No runtime dependency (self-contained port). |
| Hartigan's dip test (`diptest`) | rejected | Designed for continuous data; unreliable on 4-point ordinals (too few unique values). Adds a dependency. |
| Bimodality coefficient (skew²+1)/kurtosis | rejected | Heuristic; conflates skew with bimodality; fragile on bounded discrete scales. |

## C2 design

New detector `detect_bimodality()` added to the existing
`src/scripts/prospector/polarization.R` (keeps the whole dispersion/polarization
family in one module and reuses `.pol_slopes`).

```
detect_bimodality(freqs, out_dir=, min_waves=, flat_threshold=, bimodal_A_max=) -> tibble
```

- **Input `freqs`:** long frequency table `country, wave_num, variable, value, count`
  (one row per occupied response code per country×wave×variable; `value` and
  `wave_num` are named to match `compute_means`). The scale length `K` per variable
  is the **contiguous integer span of observed codes**, `max(value) − min(value) + 1`
  across all of that variable's waves/countries — so a never-chosen *interior*
  category still occupies its position (frequency 0) and *A* is computed on a fixed,
  correctly-positioned length-K vector for every country×wave. **Two detector-level
  guards** keep this well-defined: variables with any non-integer `value` (the
  runner's `vars` set includes normalized/continuous columns such as `*_01`, which
  have no ordinal lattice) are dropped, and variables with `K > max_categories`
  (default 11 — quasi-continuous items like 0–100 scales, not ordered rating scales)
  are excluded. The nominal-variable exclusion upstream is not sufficient on its own.
- Computes *A* per country×wave×variable, then `pol = −A`, then a per
  country×variable slope of `pol` via `.pol_slopes` (needs ≥ `min_waves`).
- Also carries `A_start` / `A_end` (first- and last-wave *A*) for the shape guard
  and for reporting.

### Classification (per country×variable)

Requires ≥ `min_waves` waves **and** `K ≥ 3` response categories (A on a 2-point
item is degenerate — excluded).

| `pattern` | Condition | Reading |
|---|---|---|
| `POLARIZING_BIMODAL` | `pol_slope > flat` **and** `A_end < bimodal_A_max` | mass moving toward the poles *and* the distribution is now genuinely split — not merely slightly-less-agreed |
| `CONVERGING_UNIMODAL` | `pol_slope < -flat` | consensus forming (agreement rising) |
| `OTHER` | everything else | shape roughly stable, or still overwhelmingly one-camp |

The **trend (`pol_slope`) is the primary signal**; the `A_end < bimodal_A_max`
guard exists only to stop an item that is still overwhelmingly unimodal (A ticked
down a hair) from being called a two-camp split. `bimodal_A_max` is eyeballed and
tunable (default **0.5** — agreement has dropped below "fairly agreed"), in the
same spirit as Pass B's `VOLATILE_THRESHOLD` / `CURVE_QUORUM`.

### Output `bimodality.csv`

Columns: `country, variable, A_start, A_end, pol_slope, pattern, c1a_pattern`.

`c1a_pattern` is **left-joined from `polarization.csv`** (produced earlier in the
same runner). That single column makes C2's payoff readable in one file:

- **C1a `POLARIZING` ∩ C2 `POLARIZING_BIMODAL`** → SD rose **and** it is a genuine
  two-camp split.
- **C1a `POLARIZING` ∩ C2 not** → SD rose but the spread is (roughly) uniform, not
  two camps.

No separate cross-tab output is emitted (YAGNI — the join column suffices).

### Wiring (`run_abs_all_countries.R`, ABS only)

Mirrors the C1a/C1b pattern. Add a `compute_freqs(data)` helper beside
`compute_means` — same `pivot_longer` to respondent-level `value`, then
`filter(!is.na(value))`, `group_by(country, wave_num, variable, value)`, and
`summarise(count = n())` (producing `country, wave_num, variable, value, count`) — then:

```r
frq <- compute_freqs(d)                       # long frequency table
bim <- detect_bimodality(frq, out_dir = OUTPUT_DIR, min_waves = MIN_WAVES,
                         flat_threshold = FLAT_THRESHOLD)
```

with the `polarization.csv` join done inside `detect_bimodality` (reads the file
from `out_dir` if present; skips the `c1a_pattern` column if absent, so the
detector is runnable standalone). ABS-only, like C1a/C1b; other runners get it
opportunistically later.

## Implementation note — computing *A* without a dependency

`agrmt::agreement()` is the canonical implementation but is **not** in `renv`, and
`polarization.R` currently depends only on tidyverse + broom. We implement a
self-contained `.vdeijk_A(freq_vec, K)` (layer-decomposition per van der Eijk
2001) and **validate it against closed-form anchors** in the tests:

- single category → **+1**
- uniform over K → **0**
- 50/50 at the two extremes → **−1**
- plus 2–3 hand-computed intermediate distributions.

During development the port is spot-checked against `agrmt::agreement()` on a batch
of random distributions **if the package happens to be installed** — a dev-time
oracle only, never a runtime import. If the from-scratch port proves too
error-prone, the fallback is to add `agrmt` to `renv` and call it directly; the
anchor tests pin correctness either way.

## Testing (extends `src/scripts/prospector/test_polarization.R`)

- **Statistic:** `.vdeijk_A` hits the three closed-form anchors (+1 / 0 / −1) and
  the hand-computed intermediates.
- **Classification:** synthetic unimodal→bimodal over waves → `POLARIZING_BIMODAL`;
  bimodal→unimodal → `CONVERGING_UNIMODAL`; a distribution that *shifts* but stays
  unimodal → `OTHER` (proves C2 is not just re-detecting a mean move).
- **Gates:** `K < 3` excluded; `min_waves` gate; NA-safety; the `bimodal_A_max`
  guard blocks a still-unimodal item whose `pol_slope` is positive.
- **`c1a_pattern` join:** present when `polarization.csv` exists, gracefully absent
  otherwise.
- The existing `test_polarization.R` C1a/C1b assertions and
  `test_signature_match.R` (69/0) stay green — C2 is a new detector, additive.

## Non-goals / notes

- **Survey weights:** unweighted frequencies as a first cut, matching the tool's
  exploratory "puzzles, not conclusions" stance. Weighted *A* is a later refinement.
- **Cross-survey wiring:** ABS is the calibration survey; C2 wires ABS only.
- **Other cleavages / subgroup bimodality:** out of scope (that is a C1b-family
  extension, not C2).
- Like every prospector output, `POLARIZING_BIMODAL` rows are **puzzles, not
  conclusions** — *A* can move from a scale reissue, a category-collapse in
  harmonization, or a sampling-frame change; check the item before interpreting.
