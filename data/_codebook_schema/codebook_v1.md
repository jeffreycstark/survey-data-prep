# Extracted-Codebook Schema v1

## 1. Purpose

The audit framework's Layer 2 (codebook reconciliation, `audit/01-audit-framework.md`)
needs a single canonical shape that every per-survey codebook extractor targets.
This document defines that shape — schema v1 of the extracted codebook.

The extracted codebook is the machine-readable analogue of the verbatim question
dictionaries already maintained per survey (e.g.
`data/abs/questionnaire_text/abs_verbatim_items.csv`). The two artifacts are
**siblings, not substitutes**: the verbatim CSV records one row per
(harmonized_name × wave) with the question stem and prose response scale; the
extracted codebook records **one row per (raw variable × response code × wave)**,
with each individual code and label exposed as its own row. The verbatim CSV is
hand-curated from official questionnaires and is the source of truth for paper
appendices. The extracted codebook is mechanically generated from the source
data (SPSS `.sav`, codebook `.xlsx`, etc.) and is the source of truth for the
diff engine that compares YAML claims against what the data actually contains.

A YAML may declare `valid_range: [1, 4]` and a missing-code convention; the
codebook shows whether codes 1–4 are actually present in the source data, what
labels they carry, and which codes the source itself flags as missing. The diff
engine (F4) performs that comparison.

## 2. Schema

One row per `(survey, wave, raw_var, response_code)` tuple.

| Column | Type | Required | Description |
|---|---|---|---|
| `survey` | string | yes | Survey slug matching the directory name in `data/<survey>/` (`abs`, `kinu`, `ipus`, `kgss`, ...). |
| `wave` | string | yes | Wave key matching the YAML `source:` keys for this survey (`w1`, `w2003`, `y1995`, `2018`, `r5`, ...). String, never numeric — preserves leading characters and avoids loss for year-keyed surveys. |
| `raw_var` | string | yes | Raw variable name as it appears in the source artifact (`q43`, `q5_3`, `uni03`, `IDENPA`). Case-preserved. |
| `question_text` | string | yes | Verbatim question stem in the source language. For battery items, may concatenate `<stem> :: <item>` so the row is self-contained. |
| `response_code` | number or string | yes | The numeric or string code as stored in the data (`1`, `2`, `-1`, `99`, `"yes"`). Type-flexible: most surveys use integer codes, but a minority use string codes (e.g. country abbreviations). Parquet column type is `string`; integer-valued codes are written as strings and parsed as needed by the diff engine. |
| `response_label` | string | yes | Human-readable label for that code (`"Strongly agree"`, `"Don't know"`, `"불가능"`). |
| `missing_code_flag` | bool | yes | `TRUE` if this code denotes missing / non-response / inapplicable / refused / DK; `FALSE` for substantive responses. Extractor decides per source-defined missing markers. |
| `source_doc` | string | optional | Path (relative to repo root) to the source codebook artifact for traceability. |
| `source_page` | int or string | optional | Page number for PDFs, sheet name for xlsx, or row index for spot-checking. |
| `language` | string | optional | ISO 639-1 code: `en`, `ko`, `ja`, `es`, `ar`, .... For surveys with multilingual codebooks, one row per (code × language) is acceptable; the diff engine deduplicates on `(raw_var, response_code)` and prefers the matching `language` when ambiguous. |
| `notes` | string | optional | Extractor-specific caveat, e.g. `"label translated by haven::as_factor"`, `"pre-Bug-5 raw category"`, `"reconstructed from spss missing-codes attr"`. |

Eleven columns; seven required; four optional. Optional columns are emitted as
the parquet null/NA when the extractor cannot populate them.

## 3. File-on-disk convention

Per-survey extractors write to `data/<survey>/codebook/`. Two valid shapes:

- **Per-wave codebook** (one file per wave): `data/<survey>/codebook/<wave>.parquet`.
  Use when each wave ships its own codebook artifact (IPUS xlsx per year, ABS
  per-wave SPSS files). The `wave` column inside the file matches the filename.
- **Cumulative codebook** (one file for all waves): `data/<survey>/codebook/<survey>_codebook.parquet`.
  Use when the survey publishes a single rolled-up codebook covering every
  wave (KINU, KGSS). The `wave` column inside the file distinguishes waves.

Both shapes are valid simultaneously for one survey if needed (e.g. a cumulative
file plus a wave-specific addendum). The diff engine reads everything matching
`data/<survey>/codebook/*.parquet` and concatenates.

A CSV fallback at the same path with a `.csv` extension is acceptable when
`arrow` is unavailable; parquet is preferred for type-safety on
`missing_code_flag` (bool) and `source_page` (int).

## 4. Sample row

Three rows from a hypothetical IPUS 2018 extraction of `uni03` (post-Bug-5 raw
six-category form):

```csv
survey,wave,raw_var,question_text,response_code,response_label,missing_code_flag,source_doc,source_page,language,notes
ipus,w2018,uni03,남북한 통일 가능 시기,1,"5년 이내 (within 5 years)",FALSE,data/ipus/raw/2018/ipus_2018_codebook.xlsx,Sheet1,ko,
ipus,w2018,uni03,남북한 통일 가능 시기,6,"불가능 (impossible)",FALSE,data/ipus/raw/2018/ipus_2018_codebook.xlsx,Sheet1,ko,
ipus,w2018,uni03,남북한 통일 가능 시기,9,"모름/무응답 (DK/NR)",TRUE,data/ipus/raw/2018/ipus_2018_codebook.xlsx,Sheet1,ko,
```

## 5. How extractors plug in

Each survey gets its own R script at `src/r/audit/extractors/<survey>_codebook.R`
(paths created by individual extractor tickets — F2 for ABS, F6 for KGSS,
later tickets for IPUS, KINU, WVS, LBS, etc.). Each script reads the survey's
source format (SPSS via `haven`, xlsx via `readxl`, PDF via `pdftools`) and
writes parquet output conforming to this schema at the path given in §3.

Extractors are free to use survey-specific logic for missing-code detection,
language tagging, and battery-stem concatenation. The schema is the contract
they agree on — what they do internally to reach it is their choice.

## 6. How the diff engine consumes it

Ticket F4 (`src/r/audit/02_check_codebook.R`) reads
`data/<survey>/codebook/*.parquet`, joins against the YAML claims discovered via
`list_survey_specs(survey)` from `src/r/utils/spec_discovery.R` (ticket A3),
and produces `audit/reports/<survey>/02-codebook-recon.csv` with one row per
(variable × wave × claim) and a `status` column of `pass | fail | unreconciled`.
The diff engine treats either file shape (per-wave or cumulative) identically
because it reads via glob and concatenates before joining.

Coverage reporting (F5) consumes the same parquet output and emits
`audit/reports/<survey>/02-coverage.json`.
