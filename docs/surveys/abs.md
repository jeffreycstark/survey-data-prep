# Asian Barometer Survey (ABS)

**Status**: Complete (330 vars, 6 waves, 113,945 respondents). W6 covers 12 countries — Japan, Singapore, Malaysia added 2026-05.

## Pipeline

```bash
Rscript src/r/data_prep_modules/0_load_waves.R
Rscript src/r/data_prep_modules/2_harmonize_all.R
Rscript src/r/data_prep_modules/99_create_final_dataset.R
```

ABS production specs are in `src/config/abs/harmonize/` (28 files), like every other survey. Until 2026-08-07 they lived in a separate `harmonize_validated/`; that exception is gone. Two never-validated drafts are parked in `src/config/abs/_drafts/` and are not loaded.

## Loading

```r
d <- readRDS("data/processed/abs_harmonized.rds")
# Or: arrow::read_parquet("data/processed/abs_harmonized.parquet")
```

Per-wave files: `outputs/master_w{1..6}.rds`.

## Key Variable Categories

| Category | Examples |
|----------|----------|
| Demographics | country, age, gender, urban_rural, education_level |
| Political Action | action_demonstration, action_petition (1-5, higher=more active) |
| Trust | trust_president, trust_parliament, trust_police (1-4, higher=more trust) |
| Democracy | dem_sat_national, dem_best_form, dem_always_preferable |
| Economy | econ_national_now, econ_family_now (1-5, higher=better) |
| Social Media | sm_use_facebook, sm_use_twitter (1=Yes, 2=No, W6 only) |
| Weights | weight (mean ~1, W3-W6), weight_cross (W3-W4 only) — continuous |

## Country Codes

1=Japan, 2=Hong Kong, 3=Korea, 4=China, 5=Mongolia, 6=Philippines, 7=Taiwan, 8=Thailand, 9=Indonesia, 10=Singapore, 11=Vietnam, 12=Cambodia, 13=Malaysia, 14=Myanmar, 15=Australia, 18=India.

## Verbatim dictionary

`data/abs/questionnaire_text/abs_verbatim_items.csv` — Complete.

## Scale-direction notes

- `democracy_satisfaction`: W2 raw 1=Not at all → 4=Very; W3–W6 raw 1=Very → 4=Not at all (REVERSED in harmonization to standard direction)
- `dem_best_form`: raw 1=Strongly agree → 4=Strongly disagree; REVERSED so 4=pro-democracy
- `dem_vs_equality`: raw "both equally" at position 5; REMAPPED to center (3)
- `dem_always_preferable`: W2 response order differs; remapped to W3 standard

## W5 trust seam (6→4pt pole-merge) and the `*_w5_6pt` companions

W5 fielded 18 items on **6-point bipolar scales** that every other wave asked
as 4-point: the 13 institutional-trust items (`trust_president`, `trust_courts`,
`trust_national_government`, `trust_political_parties`, `trust_parliament`,
`trust_civil_service`, `trust_military`, `trust_police`, `trust_local_government`,
`trust_election_commission`, `trust_ngos`, `trust_television`, `trust_newspapers`),
the 4 social-trust items (`trust_relatives`, `trust_neighbors`,
`trust_acquaintances`, `trust_strangers`), and `econ_family_income_fair`.

The harmonized 4-pt columns collapse W5 by **merging both poles**
(raw 1,2 → 4; 5,6 → 1). That keeps the shape comparable but makes W5's top and
bottom bins hold TWO native categories where every other wave's hold one —
mechanically inflating W5 top-box shares and means ~2.4–4.6× (bin-width parity,
Check D; discovered via paper 05's Thailand analysis).

**Fix (2026-08-08):** each item has a native companion column
`<id>_w5_6pt` — W5-only, 1–6, reversed so higher = more trust (fairer for
`econ_family_income_fair`, whose W5 card runs 1=Very fair → 6=Very unfair).

Rules of thumb:
- **W5 levels** (means, top-box shares, distributions): use `*_w5_6pt`.
- **Cross-wave comparisons**: use the 4-pt columns W4↔W6, bypassing W5, or
  model the seam explicitly.
- W4→W5 / W5→W6 **change scores on the 4-pt columns are artefactual** — do not
  interpret them as real change.

The verbatim dictionary's W5 rows show the real 6-pt card; the 4-pt items are
exempted in `src/config/_audit/bin_width_exemptions.yml` with pointers here.

**Row identity:** every row carries the bank-wide `row_uid` (see CLAUDE.md); `country+wave+idnumber` is the native key, unique except 2 exempted HK W5 release duplicates — never join on fewer columns.
