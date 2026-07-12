# Slope Prospector (Trend Anomaly Detection)

A systematic tool for identifying interesting trend patterns across harmonized survey data. Located at `src/scripts/slope_prospector.R`. **This is a prospecting tool — findings are puzzles, not conclusions.**

## What it does

Takes long-format country-wave means and produces 10 outputs:

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

The prospector matches countries against 20 named theoretical signatures — the original 8, six Phase-1 additions, and six Phase-2 additions that use richer per-group features (magnitude, shape, endpoint level) and two structural clauses (`within`, `ordered`). The registry is `src/scripts/prospector/signatures.yml`; treat it, not this table, as the source of truth if the two ever drift.

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

### Signature DSL

Each signature in `src/scripts/prospector/signatures.yml` has `required`/`supporting` maps from a concept-group name to a **slot value**. A slot value can be:

- a bare direction — `RISING`, `FALLING`, or `FLAT`;
- a list of directions — e.g. `[FALLING, FLAT]`;
- a condition map with any of `dir`, `magnitude` (`SLOW`/`FAST`), `shape` (`STEADY`/`REVERSED_UP`/`REVERSED_DOWN`/`ACCELERATING`/`DECELERATING`), `level` (`LOW`/`MID`/`HIGH`) — evaluated against the enriched group feature frame built by `signature_features.R` (`magnitude_tier`, `shape`, `ends_level`).

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

`src/scripts/prospector/signatures.yml` is the editable registry — add or edit a signature there; no R changes are needed for a new combination of `required`/`supporting`/`level`/`within`/`ordered` against existing groups. One gotcha: the structural-break wave that `ordered` depends on comes from `strucchange::breakpoints(..., h = 3)`, which needs at least 2×h = 6 waves of data to locate a break. For a concept group whose member series run shorter than 6 waves, `broke_at_wave` is `NA` and any `ordered` clause referencing that group will not fire.

## Input format

The prospector expects a CSV with columns:
- `country`: country name or code
- `wave_num`: numeric wave indicator
- `variable`: harmonized variable name
- `mean_value`: country-wave mean
- `n` (optional): respondent count for weighted least squares

Runner scripts (e.g., `run_abs_all_countries.R`) handle the pivot from wide harmonized RDS to this long format.
