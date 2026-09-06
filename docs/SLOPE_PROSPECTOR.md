# Slope Prospector (Trend Anomaly Detection)

A systematic tool for identifying interesting trend patterns across harmonized survey data. Located at `src/scripts/slope_prospector.R`. **This is a prospecting tool — findings are puzzles, not conclusions.**

## What it does

Takes long-format country-wave means and produces **10 core outputs**, plus **3 dispersion outputs** from the Pass C add-on module (`src/scripts/prospector/polarization.R`, currently wired into the ABS runner only — see [Dispersion / polarization (Pass C)](#dispersion--polarization-pass-c)):

| Output | Purpose |
|--------|---------|
| `outlier_slopes.csv` | Country-variable pairs with unusually steep slopes (\|z\| > threshold), standardised against the reference distribution named in `z_basis` |
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
CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"  # per-survey; see table below
SIGNATURES_PATH     <- "src/scripts/prospector/signatures.yml"  # per-survey; see below

# Optional tuning
MIN_WAVES           <- 3       # minimum waves to estimate a slope
Z_THRESHOLD         <- 2.0     # outlier z-score cutoff
Z_BASIS             <- "auto"  # "auto" | "cross_country" | "cross_variable"
FLAT_THRESHOLD      <- 0.05    # |variable slope| below = "FLAT" (DIRECTION_BASIS "slope")
GROUP_FLAT_THRESHOLD <- 0.05   # |group mean slope| below = "FLAT"; defaults to FLAT_THRESHOLD
DIRECTION_BASIS     <- "slope" # "slope" | "sd_units" — how a variable's direction is decided
DIRECTION_SD_THRESHOLD <- 0.2  # SDs of change over the window (DIRECTION_BASIS "sd_units")
USE_WEIGHTED_SLOPES <- TRUE    # use n column for WLS if available
DO_CLUSTERING       <- TRUE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE

source("src/scripts/slope_prospector.R")
```

## Existing runner scripts

| Script | Scope | Output Directory |
|--------|-------|-----------------|
| `src/scripts/run_abs_all_countries.R` | All 16 ABS countries, 360 vars, 6 waves | `outputs/prospecting/abs_all/` |
| `src/scripts/run_korea_abs.R` | All ABS countries (Korea-focused) | `outputs/prospecting/korea_abs/` |
| `src/scripts/run_kgss_prospector.R` | KGSS, Korea only, 17 survey years | `outputs/prospecting/kgss/` |
| `src/scripts/run_afro_prospector.R` | Afrobarometer, R1–R9 | `outputs/prospecting/afro_all/` |
| `src/scripts/run_lbs_prospector.R` | Latinobarómetro, 1995–2024 | `outputs/prospecting/lbs_all/` |
| `src/scripts/run_kinu_prospector.R` | KINU, Korea only | `outputs/prospecting/kinu/` |
| `src/scripts/run_ipus_prospector.R` | IPUS, Korea only | `outputs/prospecting/ipus/` |

## Concept group files

| File | Survey | Groups |
|------|--------|--------|
| `src/scripts/concept_groups.yml` | ABS | 27 groups (trust, democracy, efficacy, economic, media, etc.) |
| `src/scripts/concept_groups_kgss.yml` | KGSS | 25 groups (institutional confidence, national identity, ISSP modules, etc.) |
| `src/scripts/concept_groups_afro.yml` | Afrobarometer | trust, democracy, economic, clientelism |
| `src/scripts/concept_groups_lbs.yml` | Latinobarómetro | trust, democracy, economic, crime |
| `src/scripts/concept_groups_kamos.yml` | KAMOS | 11 groups (trust, economic, political, mobility, etc.) |

**Every group must be direction-consistent.** The group mean slope averages its
members, so one inversely-valenced item cancels its group-mates and makes both
`group_direction` and `coherence_score` uninterpretable. KGSS hit this three
times (immigration, national pride, international attitudes) — see the
single-country section below.

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

**KGSS registry (19)** — a separate file, `src/scripts/prospector/signatures_kgss.yml`,
written in the KGSS concept-group vocabulary. Same DSL, no engine difference.
Point `SIGNATURES_PATH` at it (the KGSS runner does).

| ID | What It Detects |
|----|------------------|
| `confidence_collapse` | Political and civic/service institutions losing confidence together |
| `systemic_delegitimation` | Confidence falling in political AND economic/security institutions |
| `selective_legitimation_kr` | Executive confidence rising while legislature and courts lose it (`within`) |
| `fractured_political_confidence` | `conf_political` splits — one institution clearly rising while another falls |
| `delegitimation_sequence` | Political confidence breaks downward before participation does (`ordered`) |
| `efficacy_trap_kr` | Internal efficacy rising while external efficacy falls (`within`) |
| `alienation_withdrawal_kr` | Efficacy and political action falling together |
| `democratic_disillusionment` | Democracy rated worse now *and* expected worse in ten years (`within`) |
| `nostalgic_declinism` | The remembered past rated increasingly democratic as the present is rated less so (`within`) |
| `economic_pessimism_kr` | Economic expectations fall while present evaluations hold up |
| `private_public_decoupling` | Wellbeing holds or rises while evaluations of government and economy fall |
| `inequality_grievance` | Perceived inequality rising while political evaluations do not improve |
| `anticorruption_decoupling` | Perceived corruption rises even as anti-corruption performance is rated the same or better |
| `corruption_resignation` | Perceived corruption rising while political confidence falls |
| `immigration_hardening` | Immigration seen as more threatening while its perceived benefits decline |
| `ethnic_closure` | Ascriptive "true Korean" criteria hardening alongside immigration threat |
| `nationalist_turn` | Protectionist/nationalist positions rising, national pride not falling |
| `statist_turn` | Demand for government spending rising, demand for responsibility not falling |
| `civic_norm_erosion` | Importance of civic duties falling, civic rights not rising to compensate |

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

## Single-country runs (KGSS, KINU, IPUS)

The prospector was built on ABS, where the unit of comparison is the country.
Four of its defaults quietly stop working when a run has only one, and a
single-country run will still exit 0 while producing empty or misleading files.

**1. Outlier z-scores need a different reference, and a different statistic.**
`z_slope` standardises against a reference distribution. With more than one
country that is *the other countries' slopes on the same variable*
(`cross_country`); with one country the reference has a single member and every
z collapses to 0, so `outlier_slopes.csv` is empty **by construction**, not by
finding. `Z_BASIS` (default `"auto"`) switches to `cross_variable` — *the same
country's other variables* — when the data holds one country.

Switching the reference is not enough on its own, because normalization is
per-variable: with one country each series is min-max stretched to exactly
[0, 1] over its own range, which destroys magnitude and caps the slope at
`1/span`. A 3-wave/4-year series tops out at 0.25/yr while a 17-wave/22-year one
tops out at 0.045/yr, so ranking raw slopes across variables ranks series
length. `cross_variable` therefore standardises one of two things, named in the
`z_stat` column:

| `z_stat` | Quantity | When |
|---|---|---|
| `raw_slope` | the slope itself | always, under `cross_country` |
| `sd_units` | `slope x norm_range x wave_span / sd_typ` — change across the observed window in respondent-level SDs | means table has an `sd_value` column |
| `traversal` | `slope x wave_span` — share of its own range the series covered | fallback; really a *monotonicity* measure, so rankings under it are weak and the run prints a warning |

**Emit `sd_value` from the runner** (`sd(value, na.rm = TRUE)` alongside
`mean_value`) for any single-country survey; the ABS and KGSS runners do. Without
it the outlier list ranks how steadily variables moved, not how far.

A z is never comparable across bases: 3 means "steepest across countries" under
one and "moved most in SD terms among everything this survey measures" under the
other. Basis and statistic are printed at run time, stamped into
`prospecting_report.md`, and carried in `z_basis` / `z_stat` columns.

**2. Signatures are written in a survey's own group vocabulary.**
`signatures.yml` names ABS groups. KGSS shares three of those names, so a KGSS
run against it matched nothing — and "0 narrative pattern matches found" reads
as a substantive result about Korea rather than a matcher with nothing to match
on. Point `SIGNATURES_PATH` at a registry written in the run's own concept-group
names (`prospector/signatures_kgss.yml`). The invariant — every group and
`within` variable a registry names must exist in the paired concept-group file —
is enforced by `prospector/test_signatures_kgss.R` for both surveys.

**3. Group flat bands are in wave units, which differ by survey.** An ABS wave
is four years (median interview year 2002/2007/2011/2015/2019/2022); a KGSS wave
is one calendar year. ABS's `FLAT_THRESHOLD` of 0.05 per wave is 0.0125 per
year, so applying 0.05 to per-year KGSS group means put 22 of 24 groups in the
flat band and no signature could fire whatever the vocabulary. Set
`GROUP_FLAT_THRESHOLD` in the wave unit the run actually uses; it defaults to
`FLAT_THRESHOLD`, so multi-year-wave surveys are unaffected. Note the split:
*variable*-level slopes stay on `FLAT_THRESHOLD` because min-max normalization
fills each series' observed range regardless of its length, leaving those slopes
noise-dominated and roughly span-independent; averaging over group members
strips that noise and leaves a trend that really is in wave units.

**4. Country clustering is meaningless** — set `DO_CLUSTERING <- FALSE`.

**5. Variable direction has the same span problem, and the same fix.**
`direction` (RISING/FALLING/FLAT) answers "is this variable moving?", and the
default rule answers it in wave units: `|slope|` against `FLAT_THRESHOLD`. Since
per-variable min-max normalization caps the slope at `1/span`, a KGSS series
running 2003-2025 tops out at 1/22 = 0.045 — below the 0.05 band — so a
long-running variable could never read RISING or FALLING however far it actually
moved. `pride_social_security` runs 1.92 to 2.89 on a 1-4 scale, a shift of 1.39
respondent SDs, and read `FLAT`.

`DIRECTION_BASIS <- "sd_units"` decides direction by magnitude instead: the
change across the observed window in respondent SDs, against
`DIRECTION_SD_THRESHOLD` (0.2 by default; the median KGSS variable moves 0.24).
It is comparable across response scales and series lengths and needs the same
`sd_value` column as `z_stat: sd_units`. Default stays `"slope"`, so ABS is
untouched.

Lowering `FLAT_THRESHOLD` instead is *not* equivalent, and is worse: it is the
right unit conversion (0.05 per 4-year ABS wave = 0.0125 per year) but per-year
slopes are noise-dominated and tightly clustered, so 0.0125 makes 90% of KGSS
variables non-FLAT and takes `divergent_pairs.csv` from 348 to 3,481 of the
8,778 possible pairs — the output stops discriminating. `sd_units` at 0.2 SD
lands at 46% non-FLAT and 1,221 pairs.

**`direction` is the single source of truth.** The divergence pre-filter and the
`n_rising`/`n_falling`/`n_flat`/`rising_vars`/`falling_vars` columns of
`slope_groups.csv` all read that column rather than re-deriving a slope
comparison; re-deriving one is how `DIRECTION_BASIS` silently stops taking
effect. The group *mean* is classified separately, against
`GROUP_FLAT_THRESHOLD`.

Two further traps are not single-country-specific but bit KGSS hardest:

- **Exclude nominal codes.** A slope on `region` (1=Seoul … 7=Jeju) or
  `marital_status` measures nothing but code distribution drift. Before the KGSS
  runner's exclusion list was extended, four such variables sat in its top twenty
  "significant structural breaks."
- **Keep concept groups direction-consistent** (see the note under *Concept
  group files*). KGSS's `immigration_attitudes` pooled three higher=more-hostile
  items with two higher=more-favourable ones, so a uniform hardening of opinion
  cancelled to a near-flat, permanently `DIVERGENT` group. Split into
  `immigration_threat` and `immigration_benefit`, the same shift surfaces as a
  fired `immigration_hardening` signature.

**Not yet done:** `run_kinu_prospector.R` and `run_ipus_prospector.R` point at
`concept_groups_kinu.yml` / `concept_groups_ipus.yml`, neither of which exists,
so both skip group analysis and narrative matching entirely. They inherit the
`Z_BASIS` fix but still need concept groups, a signature registry, an `sd_value`
column and a per-year `GROUP_FLAT_THRESHOLD`.

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
