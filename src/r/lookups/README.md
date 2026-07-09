# src/r/lookups/

Paper-time lookup helpers. Distinct from `src/r/utils/`, which holds
harmonization-engine functions called from YAML specs.

## When to use

When a paper needs to attach context to harmonized rows that the
harmonization engine deliberately does not bake in. The first such case is
cross-wave party identity: ABS partisanship YAML stores only `has_party_id`
and `party_closeness` because raw per-wave codes have no consistent meaning;
the cross-wave map lives in `data/processed/party_id_crosswalk.csv` and is
joined on demand.

## `party_lineage.R` — `join_party_crosswalk()`

Adds `party_lineage` and `coalition` columns to any data frame with country,
wave, and a per-wave party-code column. Wraps the join logic that papers
have been duplicating manually.

### Coverage

Crosswalk currently covers Korea / Taiwan / Thailand × W2-W6. Other
(country x wave) combinations get NA columns and a one-time warning naming
the missing combo. To extend, edit
`data/processed/create_party_crosswalk.R`.

### Example — replacing a manual join

Paper 92b (`31_party_fe_robustness.R`) currently joins the crosswalk by
hand. The same operation as a single call:

```r
source(here::here("src", "r", "lookups", "party_lineage.R"))

abs_w3 <- readRDS(here::here("outputs", "master_w3.rds"))

abs_w3 <- abs_w3 |>
  dplyr::mutate(wave = "W3") |>
  join_party_crosswalk(
    country_col = "country",
    wave_col    = "wave",
    code_col    = "q47"   # raw partisanship code in W3
  )

# abs_w3 now has party_lineage and coalition columns appended.
```

### Behavior on misses

- **(country x wave) not in crosswalk** (e.g., Cambodia W6): all rows get
  NA, one `warning()` per missing combo.
- **(country, code, wave) miss within a covered (country, wave)**: NA, no
  warning. Treated as legitimate "Other / minor party / refused".
- **Column conflict** (df already has `coalition`): hard error unless
  `suffix` is passed.

### Multiple party-code columns

Pass distinct suffixes:

```r
df |>
  join_party_crosswalk("country", "wave", "party_id",   suffix = "_id") |>
  join_party_crosswalk("country", "wave", "party_pref", suffix = "_pref")
```

## `kipa_bribery_series.R` — `kipa_bribery_series()`

Returns the per-year rate for `corr_bribery_experience_1yr` in the KIPA
Corruption Survey, computed under **both** denominators so a caller cannot
silently pick the wrong one.

From 2016 onward KIPA routes the bribery item only to respondents who cleared a
prior official-contact screener, so roughly half of each annual sample is
skipped (비해당, stored as `-1` and collapsed to `NA` in the harmonized file,
where it is indistinguishable from a refusal). The naive
`mean(x == 1, na.rm = TRUE)` therefore returns a rate *conditional* on official
contact from 2016 on — about 2x the population rate — and manufactures a
spurious uptick at the 2015→2016 boundary (1.90% → 3.46% conditional, versus
1.90% → 1.60% unconditional).

- `uncond_pct` — denominator is the full annual sample; routed-out respondents
  are structural zeros (no official contact implies no bribe to an official).
  **This is the series to use** for trends and for triangulation against a
  full-population measure such as ABS witnessed corruption.
- `cond_pct` — denominator is answerers only. Not comparable across 2015/2016.

Caveat that survives the correction: KIPA is a specialty sample (corporate
employees and self-employed with regular government contact), so even
`uncond_pct` is a within-frame prevalence, not a general-population rate.

```r
source(here::here("src", "r", "lookups", "kipa_bribery_series.R"))
series <- kipa_bribery_series()
series[, c("year", "n", "yes", "uncond_pct", "cond_pct")]
```

Underlying analysis: `results/paper17_kipa_bribery_denominator.R`.

## Tests

```bash
Rscript src/r/lookups/test_party_lineage.R
Rscript src/r/lookups/test_kipa_bribery_series.R
```

`test_party_lineage.R` — two checks: a 5-row synthetic spec (Korea code 301 W3 →
Uri/Democratic lineage / progressive) and a regression sample against
`data/processed/party_winner_loser.csv`.

`test_kipa_bribery_series.R` — a synthetic denominator check plus a regression
check against `data/processed/kipa_corruption_harmonized.rds` (anchor years,
the 2015→2016 gate behaviour, and exclusion of the unmapped 2022–2023 waves).

## Out of scope

- Electoral context (`winning_coalition`, `is_winner`) — those live in
  `data/processed/party_winner_loser.csv` and may eventually get their own
  helper, `join_electoral_context()`. Not built yet.
- Engine-side derivation. If a future paper needs a derived
  `party_camp` column directly in `abs_harmonized.rds`, add a `derive`
  method to `partisanship.yml` that points at the same crosswalk.
