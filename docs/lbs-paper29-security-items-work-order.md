# Instructions for CC (survey-data-prep) — Latinobarómetro additions for Paper 29

**Repo to work in:** `survey-data-prep` (lbs pipeline). **Requested by:** paper-bank paper 29
(Veiga, Ribeiro & Borba 2022 — "security voting": crime victimization / subjective insecurity →
presidential approval; extension = incumbent-ideology moderator).

**Scope note (updated 2026-07-07):** paper 29 itself is **not being pursued** (the ideology-moderator
extension is too speculative). But these four items — crime victimization, fear of crime, presidential
approval, respondent sex — are **general-purpose Latinobarómetro variables** worth having in the shared
harmonized dataset for any future LBS work, so the harmonization is still requested as **infrastructure**.
No paper-side follow-up (no `incumbent_ideology`, no models) is planned.

**What this is:** harmonize four Latinobarómetro items into `lbs_harmonized` that are not currently in
the file. Feasibility verified by reading the raw yearly `.sav` variable
labels + value labels (2018 confirmed in full; other years' codes pinned below). Follow the existing
LBS convention: one YAML spec per concept in `src/config/lbs/harmonize/`, per-year `source:` map,
derived recodes, verify against value labels (`run_lbs_prospector.R` / `concept_groups_lbs.yml` help
pin the codes I flag `[verify]`).

**Latinobarómetro gotcha:** variable codes are renamed almost every year (the `STGBS`/`ST` suffixes are
generic, NOT item-specific). So each item must be mapped per year against the value labels, not by name.

## Target years
**All available years** where each item exists (1995–2024) — these are general-purpose items, so map
them wherever present rather than restricting to a paper window. Victimization / fear-of-crime /
approval have been fielded across many rounds; the per-year codes I pinned below are a starting set,
extend via the prospector. Report per-item year coverage.

## Items to harmonize

### 1. `pres_approval` — presidential approval (DV)
"Do you approve or disapprove the way [president] is leading the country?" Recode **1=Approve → 1,
2=Disapprove → 0**; negatives → NA. Binary.
- source: 2018 `P20STGBSC`, 2020 `P17STGBS`. **Other years `[verify]`** — core LB item but not every
  year; find via the "approve/disapprove … president" label (distinct from the many `*STGBS` economic
  items). If a year lacks it, mark null and note (that year drops from the analysis).

### 2. `crime_victim` — crime victimization (IV)
"Have you or a relative been assaulted / victim of a crime in the last 12 months?" Raw values
**1=You, 2=Relative, 3=Both → 1 (victimized); 4=No → 0**; negatives → NA. Binary. Some years split
into self/relative (`.1`/`.2` or `.A`/`.B`) — combine to "any victimization = 1".
- source: 2015 `P60ST`, 2016 `P37ST`, 2017 `P65ST.A`+`P65ST.B`, 2018 `P69ST.1`+`P69ST.2`,
  2020 `P64ST`, 2023 `P58ST`, 2024 `[verify]`.

### 3. `crime_fear` — subjective insecurity (IV)
"How often do you worry that you may become the victim of a violent crime?" Raw **1=All/almost all the
time … 4=Never**. **Reverse-orient** so higher = more insecure (`fear = 5 − raw`, → 1=Never … 4=All the
time), or keep raw and document orientation. Ordinal 1–4; negatives → NA.
- source: 2015 `P57ST`, 2017 `P66ST`, 2018 `P70ST`, 2020 `P65ST`, 2023 `P59ST`, 2016/2024 `[verify]`.

### 4. `female` — respondent sex (control; not currently harmonized)
From `SEXO` (1=Man, 2=Woman) → `female = as.integer(SEXO == 2)`. 2015 uses `S12`. Present all years.

## Missing-value convention (Latinobarómetro)
Send to NA: −1 (Don't know), −2 (No answer/Refused), −3 (Not applicable), −4 (Not asked), −5 (Missing),
and 0/9x variants — verify per item against value labels.

## Run + QC
Standard LBS pipeline (`0_load_waves.R` → `2_harmonize_all.R` → `99_create_final_dataset.R`), then
per-year non-missing coverage for each new column; `pres_approval` ∈ {0,1}; `crime_victim` ∈ {0,1};
`crime_fear` ∈ [1,4]. Report the set of years where **all three of approval + victimization + fear**
are present — that is paper 29's usable window.

## NOT your job (paper-bank builds in-repo)
- **`incumbent_ideology`** — each country×year president's left/right placement (the extension's
  moderator). Paper 29 hand-codes this from external sources (e.g., V-Party / DPI / expert coding),
  exactly as paper 22 built tenure/competitiveness in-repo. Do not attempt it here.

## Summary — what you're adding
| New column | Source (per year, `[verify]` = pin via prospector) | Recode |
|---|---|---|
| `pres_approval` | 2018 P20STGBSC, 2020 P17STGBS, others `[verify]` | 1→1, 2→0 |
| `crime_victim` | 2015 P60ST, 2016 P37ST, 2017 P65ST.A/B, 2018 P69ST.1/.2, 2020 P64ST, 2023 P58ST | {1,2,3}→1, 4→0 |
| `crime_fear` | 2015 P57ST, 2017 P66ST, 2018 P70ST, 2020 P65ST, 2023 P59ST | reverse to higher=more insecure |
| `female` | SEXO (S12 in 2015) | ==2 → 1 |
