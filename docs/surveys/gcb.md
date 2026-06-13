# GCB (Global Corruption Barometer — Transparency International)

**Status**: Scaffold (22 vars, 1 edition: Asia 2020, 19,416 respondents, 17 countries). Region-extensible — built to accept additional regional editions as new "waves".

⚠️ GCB's release unit is a **regional edition**, not a year. This scaffold harmonizes the **Asia 2020 (Edition 10)** file. Other regions (Africa, Latin America, EU, etc.) and earlier global editions are separate downloads; drop each under `data/gcb/raw/<edition>/` and register it (see below). Cross-edition variable-name consistency is **unverified** until a second edition lands — that is the immediate next test.

## Regional editions — inventory & structural comparison

GCB editions do **NOT** share a common structure. Five editions are on disk under `data/gcb/raw/<edition>/`:

| Edition | Folder | Microdata? | N / countries | Var naming |
|---|---|---|---|---|
| Asia 2020 (Ed. 10) | `asia2020/` | ✅ `.sav` | 19,416 / 17 | descriptive (`CORRCHANGEFIN`, `BRIBE1FIN`, `TCOUNTRY`) |
| Pacific 2021 | `pacific2021/` | ✅ `.sav`/`.dta` | 6,144 / 10 | generic (`Q4_1`, `Q9_1`, `COUNTRY`) |
| Africa 2019 | `africa2019/` | ❌ aggregate only | — | — |
| LAC 2019 | `lac2019/` | ❌ aggregate only | — | — |
| MENA 2019 | `mena2019/` | ❌ aggregate only | — | — |

**Three of five are aggregate-only** — Africa/LAC/MENA 2019 ship country-level "Full Results" spreadsheets + questionnaire/methodology docs but **no respondent file**, so they cannot be row-bound with the microdata editions. Harmonize them only if TI releases (or you obtain) the underlying microdata.

**The two microdata editions differ at every level** (Asia 2020 vs Pacific 2021):
- **Names**: 101 columns each, **0 shared names**. Asia uses descriptive `…FIN`; Pacific uses generic `Q#` (`COUNTRY` vs `TCOUNTRY`).
- **Codes differ even where concepts match**:

  | Concept | Asia 2020 | Pacific 2021 |
  |---|---|---|
  | Corruption salience | `TQ2` 0–3 (DK=4) | `Q2a` 1–4 (DK=99) |
  | Govt fighting corruption | `CORRGOVRESFIN` 1–4 | `Q5` 1,2,**4,5** (gap at 3) |
  | Change in corruption | `CORRCHANGEFIN` 0–4 | `Q4_1` 1–5 |
  | Service bribery | `BRIBE1FIN` 0–3 + 5=No contact | `Q9_1` 1–4 (no-contact handled by separate `Q8` filter) |
  | Gender | `DEMGENDERFIN` 1/2 | `SC10`/`GENDER` 1/2 (same) |

- **Restructured batteries**: Pacific splits service contact (`Q8`), bribe (`Q9`), and favours (`Q10`) into parallel 6-item batteries, and adds institutional-confidence (`Q1a`, 9 items) and who-is-corrupt (`Q6`, 14 items) batteries that Asia organizes differently.

**Implication**: the per-edition `source:` mapping handles the name differences, but harmonizing Pacific requires **per-edition recode rules** (0-based vs 1-based scales, different DK codes, scale gaps) — not just a name remap. This is the cross-edition inconsistency the design anticipated; it is confirmed, not hypothetical.

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
3. Add `<edition_key>: <RAWVAR>` to each variable's `source:` block in `src/config/gcb/harmonize/*.yml`. For Pacific 2021 (and likely any non-Asia edition) you will **also** need a per-wave `harmonize:` rule because the response codes differ (0-based vs 1-based, different DK codes, scale gaps) — a `source:` remap alone is insufficient. See the comparison table above.
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

`data/gcb/questionnaire_text/gcb_verbatim_items.csv` — **Done** (22 rows, 1 edition asia2020; 1:1 with the harmonized dataset). Verbatim question text + response scales sourced from the official codebook (`210114_GCB10_Asia_Codebook_Final_AFG.xlsx`) and master questionnaire (`GCB_2020_Asia_Master_Questionnaire_Final.docx`), **not** SPSS labels. Bribery items carry a shared `stem_text`; harmonization transforms (acc_performance neutral-recode, report_without_fear binary, bribery no-contact→NA, education condensed) are documented in `notes`. Source documents copied to `data/gcb/questionnaires/originals/`.

## Not yet done (next steps)

- Codebook extractor (`src/r/audit/extractors/gcb_codebook.R`) → unlocks the Layer-2 coverage reconciler.
- ~~Verbatim question dictionary~~ — done (see above).
- Remaining GCB items not yet harmonized: sextortion (TQ17), right-to-information (TQ25A/B), COVID corruption (Q32_Asia), bribe reporting/solicitation, personal-connections battery (PERSONAL1–6), occupation/income/area-type demographics.
