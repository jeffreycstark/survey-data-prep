# `abs_fieldwork_years.csv` — ABS interview years the data does not carry

**Created 2026-08-09.** Scope: **gaps only.** This lookup exists to hold interview years for the
country×wave cells where the ABS release carries no date at all. Everything else comes from the data
and must keep coming from the data — do not populate this file with years that `int_year` already
supplies, or the two will drift.

## Why it exists

`int_year` is sourced per wave from the release files:

| Wave | Source | Coverage after the 2026-08-09 W1 fix |
|---|---|---|
| W1 | `yrsurvey` | **100%** (was `ir007_3`, empty for Korea and Mongolia) |
| W2 | `ir9_3` | 74.6% — four countries have no date at all |
| W3 | `ir9` (Date object) | 94.8% — Singapore has none |
| W4–W6 | `year` / `Year` | 100% |

The remaining gaps, confirmed against the post-fix harmonized file:

| Country | Wave | Rows | int_year |
|---|---|---|---|
| Korea | 2 | 1,212 | 0% |
| Philippines | 2 | 1,200 | 0% |
| Thailand | 2 | 1,546 | 0% |
| Singapore | 2 | 1,012 | 0% |
| Singapore | 3 | 1,000 | 0% |
| Mainland China | 2 | 5,098 | 98.8% (59 cases — not a country-level gap) |
| Mainland China | 3 | 3,473 | 99.9% (a handful — not a gap) |

For the four W2 countries the **entire `ir9_*` block** (day, month AND year) is empty, W2's merge has
no `yrsurvey` equivalent, and no column anywhere in those rows holds a value between 2000 and 2010.
Verified column-by-column. This is a release gap, not a mapping bug: the W2 instrument does contain
`IR10 Date of Interview` (see `data/abs/raw/wave2/ABS2_Interview Record20170220.docx`), so those
countries were asked and did not return it.

`idnumber` does not help — it is a per-country sequential counter with no year component.

## Status vocabulary

- **`provisional`** — a year is recorded but rests on a secondary source (a catalogue record or a
  search-reported figure), not on a primary document read directly. **Do not wire into the spec.**
- **`unresolved`** — no year found. The `year` column is deliberately blank rather than inferred.

## Evidence tiers

- **A** — from the data itself. Nothing in this file is tier A by construction.
- **B** — secondary source: catalogue records, fieldwork-report references. Provisional.
- **C** — no usable source yet.

## What would close each row

1. **Korea W2** — the ABS Korea second-wave country report, or the GHDx record read directly (it
   returned HTTP 403 to an automated fetch; a browser will get it).
2. **Singapore W2** — "Singapore Country Report, Second Wave of Asian Barometer Survey"
   (academia.edu/1093743).
3. **Thailand W2** — Albritton & Bureekul, *Thailand Country Report: Public Opinion and Political
   Power in Thailand (Second Wave of Asian Barometer Survey)*, 2007. Read the fieldwork section; the
   2007 publication date is **not** the fieldwork year.
4. **Philippines W2** — no report surfaced. Social Weather Stations is the likely fieldwork partner.
5. **Singapore W3** — not yet investigated.

## Do not assume a single year per wave

The nine W2 countries that *do* report a year spread across **2004–2008**:

| Year | Countries |
|---|---|
| 2006 | Mongolia, Taiwan, Indonesia, Vietnam |
| 2007 | Japan, Hong Kong, Malaysia, China (531 cases) |
| 2008 | Cambodia, China (4,508 cases) |
| 2004 | Malaysia (1 case) |

So "ABS W2 = 2006" is wrong as a blanket rule, and China alone splits across two years. Any figure
found for the four gaps should be sanity-checked against this spread.

## How to wire it in, when the rows are no longer provisional

Coalesce **after** the in-data source so real dates always win:

```r
# in the ABS harmonize step, after int_year is built
fw <- readr::read_csv("data/lookups/abs_fieldwork_years.csv", show_col_types = FALSE) |>
  dplyr::filter(status == "confirmed") |>          # never join provisional/unresolved rows
  dplyr::select(country = country_code, wave, fw_year = year)

d <- d |>
  dplyr::left_join(fw, by = c("country", "wave")) |>
  dplyr::mutate(int_year = dplyr::coalesce(int_year, fw_year)) |>
  dplyr::select(-fw_year)
```

Add a `confirmed` status to the vocabulary when a primary document has actually been read, and record
the document in `source`. Until then this file is documentation, not an input.

## Caution for anyone building cohorts from this

`int_year` exists to support `birth_year = int_year - age`. Two things to know:

- **W1 gives year only.** The 2026-08-09 fix repointed W1 to `yrsurvey`, which has no month or day,
  so `int_day`/`int_month` remain NA for Korea and Mongolia even though the year is now present.
- **ABS W1 and W2 ship no survey weights** (`weight` / `weight_cross` are populated W3+ only). Any
  W1/W2 analysis is unweighted by necessity — not a harmonization gap, the raw files have no weight
  variable.
