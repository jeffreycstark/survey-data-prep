# Arab Barometer (AB)

**Status**: Verbatim dictionary complete; full harmonization in progress.

Waves 1–8 raw data sit in `data/arab-barometer/raw/`. Verbatim dictionary covers W1 PDF + SPSS labels.

## Pipeline (in development)

The `src/r/data_prep_modules/arab-barometer/` directory contains in-progress harmonization scripts. YAML specs go in `src/config/arab-barometer/harmonize/`.

## Verbatim dictionary

`data/arab-barometer/questionnaire_text/arab_barometer_verbatim_items.csv` — Complete (44 vars, 6 waves, 264 rows; W1 PDF + SPSS labels).

**Row identity:** `row_uid` (bank-wide); native_id W5-W8 only (W1-W4 releases carry no ID; W8 has a 2,400-row ID=0 block, kept verbatim and exempted).
