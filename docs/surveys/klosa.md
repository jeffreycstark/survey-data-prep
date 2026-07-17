# Korean Longitudinal Study of Ageing (KLoSA)

**Status**: Harmonized (43 vars, 9 waves 2006–2022, South Korea only). Built for Paper 9 (Basic Pension diff-in-disc). Full survey-level writeup is Task 12's deliverable (this page is currently a stub covering the verbatim-dictionary dependency only — see [Task 11 report](../../.superpowers/sdd/task-11-report.md)).

## Pipeline

```bash
Rscript src/r/data_prep_modules/klosa/0_load_waves.R
Rscript src/r/data_prep_modules/klosa/2_harmonize_all.R
Rscript src/r/data_prep_modules/klosa/99_create_final_dataset.R
```

Source: `data/klosa/raw/w0{1..9}_e.sav` (English-labelled SPSS releases, one file per wave).

## Verbatim dictionary

`data/klosa/questionnaire_text/klosa_verbatim_items.csv` — **scaffold** (387 rows, 43 harmonized vars × 9 waves; built by `src/r/data_prep_modules/klosa/build_verbatim_scaffold.R`).

⚠️ **Dependency pending**: we do not have the official KLoSA questionnaire booklets (PDF/HWP) on disk. Per the repo's verbatim-dictionary convention (CLAUDE.md), `item_text` should ultimately come from the official questionnaire, not from SPSS variable labels. Until those booklets are sourced, `item_text` is populated from each wave's raw SPSS variable **label** and `response_scale` from the SPSS **value-label** set (both pulled directly from the `.sav` metadata, the same method used by `audit_instrument_stability.R`) — every substantive row is flagged `notes = "... item_text from SPSS label; verbatim backfill from official questionnaire pending."`. This SPSS-label version is sufficient for the instrument-stability verdict (see `outputs/klosa/instrument_stability_audit.md`) but is **not** yet Appendix-A-ready in the sense the other surveys' dictionaries are.

**Possible future Jeff download**: the Korea Employment Information Service (한국고용정보원) publishes the KLoSA questionnaire booklets per wave (Korean; English translations exist for some waves) alongside the microdata on the KLoSA data portal. Sourcing these and re-running the backfill (replacing the SPSS-label `item_text`/`response_scale` with verbatim questionnaire text) is the natural follow-up once the PDFs are in hand — store originals under `data/klosa/questionnaires/originals/` per the repo convention.
