# Slope Prospector (Trend Anomaly Detection)

A systematic tool for identifying interesting trend patterns across harmonized survey data. Located at `src/scripts/slope_prospector.R`. **This is a prospecting tool — findings are puzzles, not conclusions.**

## What it does

Takes long-format country-wave means and produces **10 core outputs**, plus **3 dispersion outputs** from the Pass C add-on module (`src/scripts/prospector/polarization.R`, currently wired into the ABS runner only — see [Dispersion / polarization (Pass C)](#dispersion--polarization-pass-c)):

| Output | Purpose |
|--------|---------|
| `outlier_slopes.csv` | Country-variable pairs with unusually steep slopes (\|z\| > threshold) |
| `structural_breaks.csv` | Stable-then-broke patterns (supF test, p < .05) |
| `divergent_pairs.csv` | Variable pairs moving in opposite directions within a country |
| `acceleration.csv` | Early vs. late period slope changes; direction reversals |
| `slope_groups.csv` | Concept group coherence scores (do related vars move together?) |
| `slope_divergence.csv` | Cross-group divergences (e.g., trust rising while efficacy falls) |
| `country_clusters.csv` | Country similarity clustering on full slope vectors |
| `narrative_patterns.csv` | Matches against named theoretical signatures |
| `heatmap_slopes.png` | Full country x variable z-score heatmap |
| `dashboard_*.png` | Per-country concept group trajectory plots |
| `polarization.csv` | *(Pass C add-on)* Per country×variable: mean flat while within-wave **SD** moves — `POLARIZING` / `DEPOLARIZING` / `OTHER` |
| `sorting.csv` | *(Pass C add-on)* Education-cleavage subgroup **gap** widening / narrowing — `WIDENING` / `NARROWING` / `OTHER` |
| `bimodality.csv` | *(Pass C add-on)* Per country×variable: response distribution splitting into two camps over waves (van der Eijk *A*) — `POLARIZING_BIMODAL` / `CONVERGING_UNIMODAL` / `OTHER`, with `c1a_pattern` joined from `polarization.csv` |

## Running the prospector

The prospector is configured via global variables set before `source()`:

```r
# Required: long-format CSV with columns: country, wave_num, variable, mean_value [, n]
INPUT_PATH          <- "path/to/means.csv"
OUTPUT_DIR          <- "outputs/prospecting/my_run"
CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"  # or concept_groups_kamos.yml

# Optional tuning
MIN_WAVES           <- 3       # minimum waves to estimate a slope
Z_THRESHOLD         <- 2.0     # outlier z-score cutoff
USE_WEIGHTED_SLOPES <- TRUE    # use n column for WLS if available
DO_CLUSTERING       <- TRUE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE

source("src/scripts/slope_prospector.R")
```

## Existing runner scripts

| Script | Scope | Output Directory |
|--------|-------|-----------------|
| `src/scripts/run_abs_all_countries.R` | All 16 ABS countries, 315 vars, 6 waves | `outputs/prospecting/abs_all/` |
| `src/scripts/run_korea_abs.R` | All ABS countries (Korea-focused) | `outputs/prospecting/korea_abs/` |

## Concept group files

| File | Survey | Groups |
|------|--------|--------|
| `src/scripts/concept_groups.yml` | ABS | 20 groups (trust, democracy, efficacy, economic, media, etc.) |
| `src/scripts/concept_groups_kamos.yml` | KAMOS | 11 groups (trust, economic, political, mobility, etc.) |

## Narrative patterns detected

The prospector matches countries against 31 named theoretical signatures — the original 8, six Phase-1 additions, six Phase-2 additions that use richer per-group features (magnitude, shape, endpoint level) and two structural clauses (`within`, `ordered`), seven Pass-A concept-group riders, and four Pass-B primitive signatures (coherence / volatility / curvature). The registry is `src/scripts/prospector/signatures.yml`; treat it, not this table, as the source of truth if the two ever drift.

**Original 8**

| ID | What It Detects |
|----|------------------|
| `output_legitimacy` | Economic satisfaction rising while democratic quality assessment is flat/falling |
| `demobilization` | Contacting/protest collapsing while authoritarian support rises |
| `aspiration_gap` | Normative democratic preference stable while empirical assessment falls |
| `hollow_citizenship` | Voting stable/rising while contacting and protest fall sharply |
| `trust_collapse` | Both executive and intermediary institutions losing trust together |
| `selective_legitimation` | Executive trust rising while courts, parties, media fall |
| `economic_pessimism` | Present economic conditions stable while outlook deteriorates |
| `corruption_normalization` | Witnessed corruption falls while perceived systemic corruption stays high |

**Phase-1 additions (6)**

| ID | What It Detects |
|----|------------------|
| `authoritarian_drift` | Normative democratic support falling while support for authoritarian alternatives rises |
| `diffuse_specific_decoupling` | Satisfaction with democratic performance falls while diffuse commitment to democracy holds |
| `rule_of_law_erosion` | Equal-treatment / rule-of-law perceptions fall alongside weakening accountability |
| `alienation_withdrawal` | Political efficacy falls and non-electoral participation collapses together |
| `output_trust_legitimation` | Economic conditions and executive trust rise while empirical democratic quality is flat/falling |
| `accountable_dissatisfaction` | Satisfaction and executive trust fall while diffuse democratic commitment holds — accountability working |

**Phase-2 additions (6)** — the first three use `shape`/`level`/`magnitude` conditions on the enriched feature frame; the last three use the `within` and `ordered` structural clauses (see DSL below).

| ID | What It Detects |
|----|------------------|
| `coup_honeymoon` | Support for authoritarian alternatives spikes then reverts (`shape: REVERSED_UP`) |
| `authoritarian_ascendant` | Support for authoritarian alternatives rising and now at a high level (`dir: RISING, level: HIGH`) |
| `accelerating_trust_collapse` | Executive trust falling fast to a floor while intermediary trust also falls (`magnitude: FAST`, `level: LOW`) |
| `true_demobilization_sequence` | Non-electoral participation breaks downward before authoritarian support breaks upward (`ordered`) |
| `selective_accountability` | Elections seen as offering real choice while courts are seen as powerless (`within` the accountability_perceptions group) |
| `efficacy_trap` | Citizens feel more able to participate yet more convinced they have no influence (`within` the political_efficacy group) |

**Pass-A additions (7)** — rider signatures over newly-added concept groups (`illiberal_values`, `anti_pluralism`, `system_support`, `traditional_authority`, `gender_traditionalism`, `economic_nationalism`, `social_mobility`); current DSL only, no engine change.

| ID | What It Detects |
|----|------------------|
| `illiberal_drift` | Illiberal values rising while normative democratic support is flat/falling |
| `anti_pluralist_turn` | Anti-pluralism rising while authoritarian support is flat/rising |
| `system_support_erosion` | System-support battery falling alongside democratic satisfaction |
| `value_modernization` | Traditional-authority values falling (with gender traditionalism flat/falling) |
| `economic_nationalist_turn` | Economic-nationalism battery rising |
| `mobility_pessimism` | Social-mobility optimism falling |
| `illiberal_modernization_paradox` | Traditional authority falling *while* illiberal values rise |

**Pass-B additions (4)** — use the primitive DSL keys (`coherence`, `volatility`, `curvature`) exposed from signals the matcher already computes. On ABS only `fractured_democratic_support` fires (4 countries); the other three prove out on synthetic tests but their eyeballed thresholds are not met on real ABS data.

| ID | What It Detects |
|----|------------------|
| `fractured_democratic_support` | Normative democratic-support group is `DIVERGENT` (≥1 member clearly rising *and* ≥1 clearly falling) |
| `volatile_institutional_trust` | Executive-trust group `VOLATILE` (member slope dispersion above `VOLATILE_THRESHOLD`) |
| `democratic_recovery` | Empirical democratic-assessment group `CONVEX` (down-then-up, U-shaped) |
| `boom_bust_economy` | Present-economy group `CONCAVE` (up-then-down, hump-shaped) |

### Signature DSL

Each signature in `src/scripts/prospector/signatures.yml` has `required`/`supporting` maps from a concept-group name to a **slot value**. A slot value can be:

- a bare direction — `RISING`, `FALLING`, or `FLAT`;
- a list of directions — e.g. `[FALLING, FLAT]`;
- a condition map with any of `dir`, `magnitude` (`SLOW`/`FAST`), `shape` (`STEADY`/`REVERSED_UP`/`REVERSED_DOWN`/`ACCELERATING`/`DECELERATING`), `level` (`LOW`/`MID`/`HIGH`), and the Pass-B primitives `coherence` (`COHERENT`/`DIVERGENT`), `volatility` (`STABLE`/`VOLATILE`), `curvature` (`LINEAR`/`CONVEX`/`CONCAVE`) — all evaluated against the enriched group feature frame built by `signature_features.R` (`magnitude_tier`, `shape`, `ends_level`, `coherence`, `volatility`, `curvature`). Each sub-key is an AND-conjunct and is silently skipped when its feature column is absent, so mixing keys is backward-compatible.

`level` may appear either inline inside a condition map (`{dir: RISING, level: HIGH}`, e.g. `authoritarian_ascendant`) or as its own top-level `level:` clause on the signature, evaluated like `required` (e.g. `accelerating_trust_collapse`'s `level: { institutional_trust_executive: LOW }`) — both idioms in `signatures.yml` are intentional and equivalent for a single group.

Two structural clauses sit above the per-group slots:

- `within`: every named sub-variable inside a group must satisfy its own direction (evaluated against `var_slopes`, not the group frame) — e.g. `selective_accountability` requires `gov_elections_real_choice: RISING` and `gov_courts_powerless: RISING` both within `accountability_perceptions`.
- `ordered`: a temporal sequence of `{group, dir}` steps. Each step's group must have a non-`NA` structural-break wave, its direction must match, and break waves must be non-decreasing across the sequence — e.g. `true_demobilization_sequence` requires the contacting/protest group to break downward at or before the wave authoritarian support breaks upward.

Tunable globals (set in `slope_prospector.R`, overridable before `source()`):

| Global | Default | Meaning |
|---|---|---|
| `FLAT_THRESHOLD` | 0.05 | \|slope\| below this = `FLAT` |
| `FAST_THRESHOLD` | 0.15 | \|mean_slope\| above this = `FAST` magnitude |
| `ENDS_LOW` | 0.33 | normalized endpoint below this = `LOW` level |
| `ENDS_HIGH` | 0.66 | normalized endpoint above this = `HIGH` level |
| `SHAPE_QUORUM` | 0.5 | member share required to assign a group `shape` (`REVERSED_UP`/`REVERSED_DOWN`/`ACCELERATING`/`DECELERATING`) |
| `VOLATILE_THRESHOLD` | 0.15 | member slope dispersion (`sd_slope`) above this = `VOLATILE` |
| `CURVE_QUORUM` | 0.5 | member share with a same-sign quadratic term required to assign a group `curvature` (`CONVEX`/`CONCAVE`) |

`src/scripts/prospector/signatures.yml` is the editable registry — add or edit a signature there; no R changes are needed for a new combination of `required`/`supporting`/`level`/`within`/`ordered` against existing groups. One gotcha: the structural-break wave that `ordered` depends on comes from `strucchange::breakpoints(..., h = 3)`, which needs at least 2×h = 6 waves of data to locate a break. For a concept group whose member series run shorter than 6 waves, `broke_at_wave` is `NA` and any `ordered` clause referencing that group will not fire.

## Dispersion / polarization (Pass C)

The core prospector is **means-only**, so "the country's average held but its people pulled apart" — rising dissensus with a stable mean — is structurally invisible. Pass C is a self-contained add-on module (`src/scripts/prospector/polarization.R`) called from the runner *after* the prospector; the two extra columns it needs are ignored by the core engine, so wiring it in does not change any of the 10 core outputs or the narrative matches.

**C1a — within-wave SD → `polarization.csv`.** `detect_polarization(df, out_dir, min_waves, flat_threshold)` takes a long table with `country, wave_num, variable, mean_value, sd_value [, n]`. It fits a per country×variable slope on the min-max-normalized `mean_value` and, independently, on the normalized within-wave `sd_value` (WLS by `n`), then classifies:

| `pattern` | Condition | Reading |
|---|---|---|
| `POLARIZING` | `\|mean_slope\| ≤ flat` **and** `sd_slope > flat` | spread widening, mean stable — consensus fracturing |
| `DEPOLARIZING` | `\|mean_slope\| ≤ flat` **and** `sd_slope < -flat` | spread narrowing — converging |
| `OTHER` | everything else | mean is moving, or SD is flat |

Columns: `country, variable, mean_slope, sd_slope, pattern`. On ABS: 2,147 rows — **141 POLARIZING**, 221 DEPOLARIZING, 1,785 OTHER. Top hits are Hong Kong `gov_leaders_abuse_power` / `trust_national_government` / `trust_political_parties` and Singapore `sat_president_govt` / `gov_sat_national` — regime/trust items fracturing with barely-moving means.

**C1b — subgroup gaps → `sorting.csv`.** `detect_sorting(gaps_df, out_dir, min_waves, flat_threshold)` takes `country, wave_num, variable, gap [, n]` where `gap = high_subgroup_mean − low_subgroup_mean`, fits a slope on the min-max-normalized `|gap|`, and classifies `WIDENING` (`gap_slope > flat`, sorting along the cleavage), `NARROWING` (`< -flat`), or `OTHER`. Columns: `country, variable, gap_slope, pattern`. The cleavage is **education** (`education_5cat`): high = post-secondary+ (4, 5) vs. low = none/primary (1, 2); secondary (3) is dropped to sharpen the contrast, and `education*` items are excluded (cleavage-on-itself is trivial). On ABS: 2,064 rows — **443 WIDENING**, 547 NARROWING, 1,074 OTHER; the top widening education gaps are overwhelmingly Hong Kong (`action_petition`, `action_demonstration`, `gov_leaders_abuse_power`, `system_capable`).

Both detectors reuse `FLAT_THRESHOLD` for `flat`. **Caveats:** Pass C is currently wired into `run_abs_all_countries.R` only (ABS is the calibration survey); other runners get it opportunistically. Like every prospector output, `POLARIZING` / `WIDENING` rows are **puzzles, not conclusions** — a within-wave SD can rise from a sampling-frame change or a scale reissue, so check the source before interpreting. Additional cleavages (age, partisanship) are a planned extension.

**C2 — bimodality / two-camp split → `bimodality.csv`.** C1a's rising SD is
ambiguous: a distribution can spread *uniformly* or split into *two camps*. C2
resolves this with **van der Eijk's agreement *A*** (van der Eijk 2001) on the
ordinal response distribution per country×wave×variable: *A* = +1 (all mass in one
category), 0 (uniform), −1 (50/50 at the two extremes). `detect_bimodality` runs
the trend of `−A` through the same slope machinery and classifies
`POLARIZING_BIMODAL` (`−A` rising past `FLAT_THRESHOLD` **and** `A_end` below
`bimodal_A_max`, default 0.5 — a genuine split, not merely less-agreed),
`CONVERGING_UNIMODAL`, or `OTHER`. Requires ≥3 response categories. The output
carries `c1a_pattern` from `polarization.csv`, so **C1a `POLARIZING` ∩ C2
`POLARIZING_BIMODAL` = a real two-camp split**, vs. C1a `POLARIZING` ∩ C2 `OTHER`
= uniform spread. Unweighted frequencies, ABS-only wiring — same caveats as C1a/C1b.

## Input format

The prospector expects a CSV with columns:
- `country`: country name or code
- `wave_num`: numeric wave indicator
- `variable`: harmonized variable name
- `mean_value`: country-wave mean
- `n` (optional): respondent count for weighted least squares

Runner scripts (e.g., `run_abs_all_countries.R`) handle the pivot from wide harmonized RDS to this long format.
