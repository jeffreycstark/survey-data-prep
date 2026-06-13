# GCB (Global Corruption Barometer — Transparency International)

**Status**: Scaffold (22 vars, 1 edition: Asia 2020, 19,416 respondents, 17 countries). Region-extensible — built to accept additional regional editions as new "waves".

⚠️ GCB's release unit is a **regional edition**, not a year. This scaffold harmonizes the **Asia 2020 (Edition 10)** file. Other regions (Africa, Latin America, EU, etc.) and earlier global editions are separate downloads; drop each under `data/gcb/raw/<edition>/` and register it (see below). Cross-edition variable-name consistency is **unverified** until a second edition lands — that is the immediate next test.

## Pipeline

```bash
Rscript src/r/data_prep_modules/gcb/0_load_waves.R
Rscript src/r/data_prep_modules/gcb/2_harmonize_all.R
Rscript src/r/data_prep_modules/gcb/99_create_final_dataset.R
```

Raw: `data/gcb/raw/asia2020/GCB_Edition10_Asia_2020.sav` (n=19,416). Full extracted package (codebook xlsx, master questionnaire docx, methodology pdf) is in `data/gcb/GCB_2020_Asia_Methodology_and_Data_v5/`.

## Loading

```r
d <- readRDS("data/processed/gcb_harmonized.rds")
# Or: arrow::read_parquet("data/processed/gcb_harmonized.parquet")
```

- **Wave/edition key**: `wave` = `asia2020`; `region` = `Asia`.
- **Country**: `country` (1–17 numeric, per-respondent; labels in `gcb_identifiers.yml`). Japan=1, South Korea=2, Taiwan=3, India=4, China=5, … Maldives=17.
- **Row key**: use `(wave, row_id, country)` — `respondent_id` is **not unique** (16,936 distinct over 19,416 rows; IDs restart per country).

## Adding a second edition (the consistency test)

1. Drop the region's `.sav` under `data/gcb/raw/<edition_key>/`.
2. Add one row to `GCB_EDITIONS` (+ region/year) in `src/r/data_prep_modules/gcb/0_load_waves.R`.
3. Add `<edition_key>: <RAWVAR>` to each variable's `source:` block in `src/config/gcb/harmonize/*.yml` — this is exactly where cross-edition naming differences surface.
4. Re-run the pipeline, then `run_validation("gcb")`. The **completeness check** flags any concept that maps but lands all-NA in an edition; once a GCB codebook extractor exists, the **source-coverage reconciler** will flag over/under-coverage in both directions.

## Variable categories (22, starter set)

| Category | Variables | Scale / notes |
|----------|-----------|---------------|
| Identifiers (5) | country, respondent_id, weight_within (WITHINWT), weight_cross (COMBINWT), fieldwork_year | fieldwork_year (YEAR) is **sparse** (~84% NA; 2019/2020) |
| Corruption perception (3) | corr_change_perceived (0–4, higher=more corruption), corr_govt_performance (1–4, higher=better), corr_institutional_problem (0–3, higher=worse) | directions differ per item |
| Anti-corruption institutions (2) | acc_awareness (1–4), acc_performance (1–5, neutral=3, recoded from Q31B) | |
| Reporting (1) | report_without_fear (1=can report, 0=fears reprisal; recoded from Q47) | |
| Bribery experience (7) | bribe_school, bribe_clinic, bribe_id_docs, bribe_utilities, bribe_police, bribe_courts (0–3 frequency; `5=No contact`→NA), bribe_rate_overall (1=no contact, 2=had contact didn't pay, 3=paid) | flagship GCB measure |
| Demographics (4) | age (998/999→NA), age_group (1–6), gender (1/2), education (0–3) | |

## Scale / missing gotchas

- **Missing codes are per-variable** — generally 98=Refused, 99=DK, but: `CORRCHANGEFIN`/`CORRGOVRESFIN`/`BRIBETOTFIN` use **99 only**; **TQ2 codes DK as `4`** (and `99`); the bribery items use **`5`=No contact** as a structural skip (→NA here); **age uses `998`/`999`** sentinels.
- **`…FIN` vs `…FINB`**: `FIN` = frequency (0=Never…3=Often, 5=No contact); `FINB` = dichotomized (1=Paid a bribe, 2=Did not). This scaffold harmonizes the `FIN` frequency battery; add a parallel battery for the binary variant if preferred.
- **Q31B has a neutral midpoint** (1–4 bad→well plus 5=Neither), unlike Q31A (1–4). Harmonized `acc_performance` remaps neutral to the centre: 1→1, 2→2, 5→3, 3→4, 4→5.

## Verbatim dictionary

**TODO** — `data/gcb/questionnaire_text/gcb_verbatim_items.csv` not yet built. Source text from `GCB_2020_Asia_Master_Questionnaire_Final.docx` + `210114_GCB10_Asia_Codebook_Final_AFG.xlsx`.

## Not yet done (next steps)

- Codebook extractor (`src/r/audit/extractors/gcb_codebook.R`) → unlocks the Layer-2 coverage reconciler.
- Verbatim question dictionary (mandatory per repo standard before "Complete").
- Second regional edition → verify cross-edition variable-name structure.
- Remaining GCB items not yet harmonized: sextortion (TQ17), right-to-information (TQ25A/B), COVID corruption (Q32_Asia), bribe reporting/solicitation, personal-connections battery (PERSONAL1–6), occupation/income/area-type demographics.
