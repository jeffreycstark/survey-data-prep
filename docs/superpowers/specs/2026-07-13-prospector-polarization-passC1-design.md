# Prospector Dispersion / Polarization (Pass C1) — Design

Date: 2026-07-13
Branch: `feat/prospector-polarization-passC1`
Status: C1a (SD-based) implemented; C1b (subgroup gaps) next.

## Problem

The prospector is means-only. "The country's average held but its people pulled
apart" — rising dissensus with a stable mean — is structurally invisible. This
is arguably the single most consequential blind spot (polarization).

## Approach (user decision: "SD first, gaps next")

- **C1a — standard deviation** (this pass): per country×wave×variable within-wave
  SD as the dispersion statistic; run the slope machinery on the SD series and
  flag variables whose MEAN is flat while DISPERSION moves.
- **C1b — subgroup gaps** (next pass): gap between subgroups on a cleavage
  (education / age / partisanship) = sorting along a fault line.

## C1a design (implemented)

New self-contained module `src/scripts/prospector/polarization.R` —
`detect_polarization(df, out_dir, min_waves, flat_threshold)`:
- `df` needs `country, wave_num, variable, mean_value, sd_value [, n]`.
- Fits a per country×variable slope on min-max-normalized `mean_value` and on
  normalized `sd_value` (WLS by `n`), independently.
- Classifies each country×variable:
  - `POLARIZING`   — `|mean_slope| ≤ flat` AND `sd_slope > flat` (spread widening, mean stable)
  - `DEPOLARIZING` — `|mean_slope| ≤ flat` AND `sd_slope < -flat` (converging)
  - `OTHER`        — everything else
- Writes `polarization.csv` (full table with both slopes + pattern).

It is a **new output module**, not a narrative signature, because polarization
is a per-variable mean-vs-dispersion comparison the group-based signature engine
cannot express.

**Runner wiring:** `run_abs_all_countries.R` adds `sd_value = sd(value)` to the
means summarise and, after the prospector runs, calls `detect_polarization` →
`polarization.csv`. The extra `sd_value` column is ignored by the existing
prospector (verified: the 14 firing signatures are unchanged after the change).

## Validation (ABS)

2,147 country-variable rows: **141 POLARIZING**, 221 DEPOLARIZING, 1,785 OTHER.
Substantive top hits: Hong Kong `gov_leaders_abuse_power` / `trust_national_government`
/ `trust_political_parties`; Singapore `sat_president_govt` / `gov_sat_national`
/ `dem_country_past` — consensus fracturing on regime/trust items with barely
moving means. Exactly the signal the means-only tool could not see.

## Testing

`src/scripts/prospector/test_polarization.R`: synthetic classification (flat
mean + rising sd → POLARIZING; + falling → DEPOLARIZING; shifting mean + flat sd
→ OTHER), the `min_waves` gate, and NA-safety. Output pristine (`lm` perfect-fit
warnings suppressed). The signature suite (`test_signature_match.R`) stays 69/0.

## Non-goals / notes

- SD of a bounded ordinal item is a legitimate dissensus measure (spread toward
  extremes). Nominal variables are already excluded upstream.
- C1a wires ABS only (calibration survey); other runners get it opportunistically.
- `polarization.csv` is a findings surface — POLARIZING rows are puzzles, not
  conclusions (SD can rise from sampling changes or scale reissue; check before
  interpreting).
