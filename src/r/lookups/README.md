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

## Tests

```bash
Rscript src/r/lookups/test_party_lineage.R
```

Two checks: a 5-row synthetic spec (Korea code 301 W3 → Uri/Democratic
lineage / progressive) and a regression sample against
`data/processed/party_winner_loser.csv`.

## Out of scope

- Electoral context (`winning_coalition`, `is_winner`) — those live in
  `data/processed/party_winner_loser.csv` and may eventually get their own
  helper, `join_electoral_context()`. Not built yet.
- Engine-side derivation. If a future paper needs a derived
  `party_camp` column directly in `abs_harmonized.rds`, add a `derive`
  method to `partisanship.yml` that points at the same crosswalk.
