# Korean Unification Tri-Survey Panel (derived)

**46 wave-survey rows combining KGSS + KINU + IPUS unification-necessity items into one direction-aligned long-format dataset.**

Built via `src/scripts/build_korean_unification_panel.R` and plotted via `src/scripts/plot_korean_unification_trajectory.R` (figure at `outputs/figures/korean_unification_tri_survey.png`).

## Loading

```r
d <- readRDS("data/processed/korean_unification_panel.rds")
# Or: arrow::read_parquet("data/processed/korean_unification_panel.parquet")
```

## Schema

| Column | Description |
|---|---|
| `survey` | "kgss" / "kinu" / "ipus" |
| `year`, `fieldwork_month`, `decimal_year` | wave timing (decimal_year = year + (fieldwork_month - 6.5)/12) |
| `wave_label` | survey-specific wave key (`"2018"`, `"2019a"`, etc.) |
| `raw_var` | source variable name(s) |
| `mean_pro_unif` | wave mean on the harmonized scale, **all on same direction** (higher = more pro-unification) |
| `mean_pro_unif_01` | mean rescaled to 0-1 for cross-survey comparison |
| `n`, `sd` | wave sample size and SD |

## Direction alignment

Critical: KGSS `pol_unification` is reversed (5 - x) before joining the panel, since its harmonization runs higher = LESS pro-unification. KINU and IPUS are already in the right direction. After alignment, all three series are interpretable as "intensity of belief that unification is necessary".

## Coverage

KGSS 2003-2025 (15 waves), KINU 2014-2023 (13 fielding waves with sub-waves), IPUS 2007-2024 (18 annual waves). Together: 2003-2025 with multi-source coverage from 2014 onward.

## Use case

Direct input for the candidate paper #1 (post-2018 unification disillusionment) and candidate paper #2 (Pyongyang summit honeymoon) in `outputs/prospecting/korea_paper_candidates.md`.
