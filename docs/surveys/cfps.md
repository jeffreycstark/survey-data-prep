# China Family Panel Studies (CFPS / 中国家庭追踪调查)

**Status: SCAFFOLD — no data in this repo yet.** The pipeline files and YAML
specs exist and validate; every `source:` is `null` pending a discovery pass.

Institute of Social Science Survey (ISSS), Peking University. Nationally
representative longitudinal survey of Chinese individuals, families, and
communities. Waves: **2010, 2012, 2014, 2016, 2018, 2020**.

Requested by paper-bank paper 26, *"Dragon Babies and Democratic Confidence"* —
a lunar-boundary regression discontinuity on Chinese zodiac birth cohorts.

---

## ⛔ Getting the data

CFPS is **not** freely downloadable. Access requires registration plus a
data-use application to ISSS; there is no anonymous path and no third-party
mirror.

- **Apply:** `https://cfpsdata.pku.edu.cn` — the CFPS data center, all waves.
  Contact: cfpsdata@pku.edu.cn
- Secondary: [PKU Open Research Data](https://opendata.pku.edu.cn/dataverse/CFPS)
  — earlier waves only (2010/2012/2014 + a 2015 baseline); redirects to the
  official platform for current data.
- **ICPSR 36524 is a metadata-only stub.** Its own record states the data are
  not available through ICPSR. Not a fallback route.

**Request Stata `.dta`.** Value labels live inside the file (SAS keeps them in a
separate `.sas7bcat` catalog that is easy to lose); `haven::read_dta()` is the
best-tested reader; Stata 14+ is UTF-8 native, which matters for Chinese label
text. If an R `.rda` export is offered, still take the `.dta` — R conversions
often flatten labelled values to factors, discarding the numeric codes needed to
identify the missing-birth-date cases.

Place downloads in `data/cfps/raw/`. The loader discovers files by pattern
rather than hardcoding names, because CFPS release filenames carry a version
stamp and the individual-level file is called `adult` in early waves and
`person` in later ones.

---

## Pipeline

```bash
# 1. DISCOVERY — run this first, read the output, resolve variable names
Rscript src/r/data_prep_modules/cfps/00_probe_variables.R 2>&1 \
  | tee outputs/cfps/probe_console.txt

# 2. Fill in src/config/cfps/harmonize/*.yml from the probe output, then:
Rscript src/r/data_prep_modules/cfps/2_harmonize_all.R
Rscript src/r/data_prep_modules/cfps/99_create_final_dataset.R
```

Output: `data/processed/cfps_harmonized.rds` / `.parquet`.

---

## ⚠ Three things the discovery pass must resolve

These are not routine data-cleaning questions. Each can invalidate the
consuming paper's design, so resolve them before writing YAML.

### 1. Solar vs lunar birth-date reporting — identification-critical

Chinese respondents commonly report birthdays in the **lunar** calendar (农历),
disproportionately in older cohorts — exactly the 1976 and 1988 cohorts the
design leans on. The RD running variable is *days from Lunar New Year*.

A lunar-reported date read as solar does not add noise. It produces a
systematically wrong running variable, and it is wrong **in a way that
correlates with treatment**, because the two calendars diverge most precisely
around the boundary the RD sits on.

If CFPS carries a 阳历/农历 flag, harmonize it as `birth_calendar` and respect it
downstream. If it carries none, record that absence explicitly — downstream must
then treat all-solar as a *stated assumption*, not a fact.

### 2. Exact birth date, and the "only age known" code

The design needs year **and** month **and** day. CFPS reportedly marks unknown
month/day with a CTRL-D style sentinel when only age was collected. Keep that
code distinguishable from ordinary refusal: the RD sample is defined by exactly
this selection, so "how many have an exact date" must remain measurable. Do not
fold it into a generic `NA`.

The exact-date completeness rate *is* the usable-sample ceiling.

### 3. Which waves carry the political battery

CFPS rotates modules; a trust/efficacy battery present in one wave may be absent
in the next. This interacts badly with the consuming design's cohort structure:

| dragon cohort | age in the 2020 wave | usable for political attitudes? |
|---|---|---|
| 1976 | 44 | yes |
| 1988 | 32 | yes |
| 2000 | 20 | late waves only (2018/2020) |
| 2012 | 8 | **no — a child in every released wave** |

So whether the *late* waves carry the battery decides whether the design has
three usable cohorts or two. Leave `source: null` for waves genuinely lacking an
item — a null is a finding, not a gap to paper over.

---

## Scale gotchas (provisional)

- **CFPS trust is its own scale family.** Do not assume the ABS/WVS 1–4
  convention. CFPS trust items are commonly 0–10. Record the native range and
  direction per item; see CLAUDE.md's cross-survey scale section.
- **Central vs local trust are separate constructs** in the Chinese case, with a
  large and well-documented gap. Keep them as distinct columns rather than
  averaging into one index.
- **Education stays on the native ladder.** Cross-survey comparison needs an
  `edu5_from_cfps()` mapping in `src/r/utils/education.R`; until that exists,
  `education_5cat` is not derived.
- **Missing codes are PROVISIONAL** in every spec (`[-1, -2, -8, -9, -10]`).
  Resolve from `outputs/cfps/missing_code_universe.csv` and replace.

---

## Panel structure

CFPS is a genuine panel — the same individual recurs across waves under a stable
personal ID. The harmonized output is **LONG, person-wave keyed**, so cluster on
`pid` and do not treat rows as independent. Same caveat as KLoSA.

Verify the linkage with a real overlap check (share of late-wave `pid`s present
in 2010) rather than inferring a stable key from the column name.

---

## Files

| Path | Purpose |
|---|---|
| `src/r/data_prep_modules/cfps/0_load_waves.R` | Pattern-based wave discovery + load |
| `src/r/data_prep_modules/cfps/00_probe_variables.R` | **Discovery pass — run first** |
| `src/r/data_prep_modules/cfps/2_harmonize_all.R` | Standard harmonize wrapper |
| `src/r/data_prep_modules/cfps/99_create_final_dataset.R` | Stack, derive `birth_date`, save |
| `src/config/cfps/harmonize/identifiers.yml` | pid, fid, weight, interview date |
| `src/config/cfps/harmonize/birthdate.yml` | **The design-critical block** |
| `src/config/cfps/harmonize/political_attitudes.yml` | Trust + efficacy outcomes |
| `src/config/cfps/harmonize/demographics_ses.yml` | SES + boundary-balance covariates |

---

## Verbatim dictionary

**Not yet built.** Per repo convention every harmonized survey needs
`data/cfps/questionnaire_text/cfps_verbatim_items.csv`, sourced from the official
questionnaire documents (not from Stata variable labels). CFPS questionnaires are
published in Chinese and English on the ISSS site; store originals in
`data/cfps/questionnaires/originals/`.

This matters more than usual here: the consuming paper is a research note whose
entire test is the sign of a trust coefficient, so Appendix A needs exact item
wording and response-scale direction.
