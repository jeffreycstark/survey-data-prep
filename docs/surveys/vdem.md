# V-Dem Core Dataset (scaffold)

**Status**: Scaffold (27,913 country-years, 202 countries, 1789–2024). **Unit: country × year (NOT individual respondents).**

## Pipeline

```bash
Rscript src/r/data_prep_modules/vdem/99_create_final_dataset.R
```

Source: `data/v-dem/raw/v15/V-Dem-CY-Full+Others-v15.rds` (27,913 rows × 4,607 cols). Codebook: `data/v-dem/raw/v15/codebook.pdf`.

## Loading

```r
d <- readRDS("data/processed/vdem_core.rds")
# Or: arrow::read_parquet("data/processed/vdem_core.parquet")
# Raw (full): readRDS("data/v-dem/raw/v15/V-Dem-CY-Full+Others-v15.rds")  # 4,607 cols — select what you need
```

## Variables (scaffold)

| Variable | Description | Scale |
|----------|-------------|-------|
| `country_name` | Full country name | string |
| `country_text_id` | ISO 3-letter alpha code (e.g. "KOR", "THA") | string |
| `COWcode` | Correlates of War numeric code | integer |
| `year` | Calendar year | integer |
| `v2x_polyarchy` | Electoral Democracy Index | 0–1 |
| `v2x_libdem` | Liberal Democracy Index | 0–1 |
| `v2x_partipdem` | Participatory Democracy Index | 0–1 |
| `v2x_delibdem` | Deliberative Democracy Index | 0–1 |
| `v2x_egaldem` | Egalitarian Democracy Index | 0–1 |
| `v2x_corr` | Political Corruption Index (higher = more corrupt) | 0–1 |
| `v2x_accountability` | Accountability Index | 0–1 |
| `v2x_freespeech` | Freedom of Expression Index | 0–1 |
| `v2x_regime` | Regime type (0=closed autocracy … 3=liberal democracy) | 0–3 |

## Notes

- This is a scaffold — add indices from the 4,607-column raw file as papers require.
- Full variable list and definitions: `data/v-dem/raw/v15/codebook.pdf`.
- For paper-specific merges, join on `country_text_id` (ISO3) + `year`.
- Contemporary coverage is most complete from ~1900 onward.
