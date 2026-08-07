---
name: appendix-variable-builder
description: Generate Appendix A (Survey Items / Variable Descriptions) for academic papers that use harmonized survey data. Use when the user asks to create, regenerate, or audit a survey-item appendix for any paper in paper-bank. Triggers on "Appendix A", "variable table", "question wording", "codebook appendix", "survey items used", "regenerate the appendix", or any request to document which survey questions map to which analysis variables. Pulls verbatim question text, response scales, per-wave question IDs, and harmonization notes from the centralized verbatim CSVs and YAML specs in this repo, and emits paper-13-style markdown ready to paste into a Quarto manuscript.
---

# Appendix Variable Builder

Generates the "Survey Items" / "Appendix A: Variable Descriptions" section
of academic-paper online appendices from the centralized verbatim
question dictionaries (`data/{survey}/questionnaire_text/{survey}_verbatim_items.csv`)
and harmonization YAMLs (`src/config/{survey}/harmonize/*.yml`
or `harmonize/*.yml`) that live in this repo.

## When to use

When a paper's manuscript or online appendix needs a "Survey Items"
section that lists, for each harmonized variable used in the analysis:

- Verbatim question text (as read to respondents)
- Response scale with category labels
- Per-wave question IDs (since survey question numbers shift across waves)
- A harmonization note (reverse-coded, dichotomized, scale-collapsed, ...)
- For battery items that share a stem (e.g. KGSS Q35 trust battery, ABS
  authoritarian openness battery), the stem is rendered once and the items
  are listed below it.

This is the **single source of truth** for what survey items a paper uses.
The repo controls the harmonization, so this skill is positioned to keep
papers' appendices in sync with the underlying YAMLs.

## Reference template

Paper 13 (`13_authoritarian_attraction/manuscript/aa-online-appendix.qmd`,
"Survey Items" section starting at line 124) is the gold-standard format.
The generator regenerates it from the variable list alone.

## How to use

```r
source("scripts/appendix-variable-builder/build_appendix.R")

md <- build_appendix(
  survey = "abs",  # or "wvs", "kgss", "afro", "lbs", "arab-barometer", ...
  groups = list(
    "Dependent Variable: Authoritarian Openness Scale" = c(
      strongman_rule    = "Strong Leader",
      military_rule     = "Military Rule",
      single_party_rule = "Single-Party Rule"
    ),
    "Performance Controls" = c(
      democracy_satisfaction    = "Democratic Satisfaction",
      trust_national_government = "Trust in National Government",
      corrupt_national_govt     = "Corruption Perceptions",
      econ_national_now         = "Economic Evaluation"
    )
  ),
  title       = "Survey Items",
  intro       = "This section documents the verbatim question wording …",
  output_file = "manuscript/_appendix_a_variables.qmd"
)
```

The output is markdown. Paste it into the appendix, or save it to a
fragment file and include it with `{{< include _appendix_a_variables.qmd >}}`.

### Input: `groups`

Named list. Each name becomes a `## Section Heading`. Each value is a
**named character vector** mapping `harmonized_name = "Display Name"`.

The generator preserves the order you give. Group items by topical role
(Dependent Variable, Controls, Mechanism, etc.) — not by source survey,
since one paper typically uses one survey.

### Output format (per-variable)

```markdown
### Display Name (`harmonized_name`)

> *"Verbatim question text from the most-recent fielded wave with complete text."*

**Response scale:** 1=Label, 2=Label, …

**Harmonization:** [Default: …] [W1: …] [W2: …] (only when non-trivial)

**Wave QIDs:** W1 qNNN, W2 qNNN, W3 qNNN, …
```

### Battery auto-detection

When all items in a group share the same `stem_text` in the verbatim CSV,
the generator emits the battery format (stem once + items below):

```markdown
## Group Heading

**Battery stem:** "As you know, there are some people in our country …"

**Response scale (all items):** 1=Strongly disapprove, …, 4=Strongly approve

### Item 1 …
```

This matches paper 08b's KGSS Q35 trust battery treatment and paper 13's
authoritarian openness scale.

### Cross-survey papers — `build_multi_survey_appendix()`

For a paper that uses multiple surveys (e.g. ABS + KIPA like paper 17),
use the multi-survey wrapper. It emits one combined fragment with a
shared top-level heading and A1/A2/A3 sub-appendices nested beneath:

```r
build_multi_survey_appendix(
  surveys = list(
    abs = list(
      survey    = "abs",
      sub_label = "A1. Asian Barometer Survey (ABS)",
      groups    = paper17_abs_groups,
      intro     = paper17_abs_intro
    ),
    kipa = list(
      survey    = "kipa_corruption",
      sub_label = "A2. KIPA Anti-Corruption Survey",
      groups    = paper17_kipa_groups,
      intro     = paper17_kipa_intro
    )
  ),
  title       = "A. Variable Descriptions",
  intro       = paper17_intro,
  output_file = "<paper-bank>/papers/17/manuscript/_appendix_a_generated.md"
)
```

Each per-survey spec passes through to `build_appendix()` with
`heading_offset = 1L`, so its top-level heading becomes the `##`
sub-appendix label and its sections nest deeper accordingly. Result:

```
# A. Variable Descriptions
## A1. Asian Barometer Survey (ABS)
### [section 1 from ABS]
#### [item from ABS]
## A2. KIPA Anti-Corruption Survey
### [section 1 from KIPA]
#### [item from KIPA]
```

Year-based vs round-based wave keys (ABS `w1`-`w6` vs KIPA
`w2004`-`w2023` vs Afrobarometer `r1`-`r9`) are normalized in the
cross-check and rendered survey-appropriate in the QID line.

## Sources read

1. **`data/{survey}/questionnaire_text/{survey}_verbatim_items.csv`** —
   wave × question_id × harmonized_name × verbatim text. Built by the
   project's verbatim-dictionary workflow.

2. **`src/config/{survey}/harmonize/*.yml`** (with fallback to
   `src/config/{survey}/harmonize/*.yml`) — the per-survey YAML specs.
   Used for:
   - The authoritative per-wave `source:` map → "Wave QIDs" line
   - The `harmonize.default.fn` and `harmonize.exceptions.<wave>.fn` →
     harmonization note

The generator cross-checks YAML `source:` against verbatim CSV
`question_id` for each (variable × wave). Mismatches surface as warnings
on stderr so they don't silently propagate into the published appendix.

## Wave-format conventions

- ABS / WVS / Arab Barometer: `w1`, `w2`, ... → rendered `W1`, `W2`, ...
- Afrobarometer: `r1`, ..., `r9` → rendered `R1`, ..., `R9`
- KGSS / LBS / KIPA / KAMOS / KINU / IPUS (year-based): `w2003`, `y2003`
  → rendered as bare year `2003`

## Harmonization-note dictionary

Function-name → English-sentence mapping lives in
`scripts/appendix-variable-builder/recode_notes.R`. Add new entries there
when a paper exposes a recode function the dictionary doesn't yet know
(unknown functions fall through to a `Custom transformation: \`fn()\`.`
placeholder rather than silently dropping the information).

## Regression test

```bash
Rscript scripts/appendix-variable-builder/examples/test_paper13.R
```

Regenerates paper 13's Survey Items section and asserts that all 14
per-wave QID grids match the hand-written reference exactly. Use this
to check the generator after editing.

## Known limitations (v1)

1. **Some verbatim CSV rows have noisy item_text** — trailing label
   fragments from PDF extraction (e.g. `"…Completely Undemocratic
   Democratic"` on the ABS dem_country_past 1-10 scale). The generator
   faithfully surfaces what's in the CSV. Fix is to clean the source row
   in the verbatim dictionary.
2. **Sub-items of a stem-only battery render without the stem** — e.g.,
   `trust_national_government` shows up as `"The national government [in
   capital city]"` because that's the item label; the trust-battery stem
   `"How much trust do you have in …"` isn't currently in the CSV row.
   Fix is to populate `stem_text` in the verbatim CSV for the trust
   battery.
3. **Composite/derived variables** (e.g. `liberal_freespeech` constructed
   by reversing `auth_govt_censor_ideas`) are documented by passing the
   underlying raw variable as `harmonized_name` and noting the derivation
   in the display name. The generator does not (yet) synthesize composite
   definitions.

## How to extend coverage

1. **New survey support:** put a `{survey}_verbatim_items.csv` in
   `data/{survey}/questionnaire_text/` and the corresponding YAML specs in
   `src/config/{survey}/harmonize{,_validated}/`. The generator picks them
   up automatically.
2. **New recode function:** add an entry to `recode_note_table` in
   `recode_notes.R` (lowercase function name → one-sentence note).

## File layout

```
scripts/appendix-variable-builder/
├── SKILL.md              # this file
├── build_appendix.R      # generator (public: build_appendix())
├── recode_notes.R        # function-name → English-sentence map
└── examples/
    ├── paper13_spec.R    # paper 13's variable list
    └── test_paper13.R    # regression test
```
