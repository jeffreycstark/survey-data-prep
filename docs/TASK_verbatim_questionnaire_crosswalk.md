# Task: Build ABS Verbatim Questionnaire Text Crosswalk

## Goal

Create a structured reference file (`data/abs/questionnaire_text/abs_verbatim_items.csv`) that maps every ABS question number to its verbatim questionnaire text, per wave. This file will be the canonical source for Appendix A operationalization tables in manuscripts.

## Output format

CSV with columns:

| Column | Description | Example |
|--------|-------------|---------|
| `wave` | Wave identifier | `w1`, `w2`, `w3`, `w4`, `w5`, `w6` |
| `question_id` | ABS question number | `q7`, `q83`, `q90`, `q128`, `q129` |
| `harmonized_name` | Variable name from YAML config | `trust_president`, `dem_pref_best_form` |
| `section` | Questionnaire section header | `B. Trust in Institutions` |
| `stem_text` | Battery intro/stem if applicable | `I'm going to name a number of institutions. For each one, please tell me how much trust do you have in them?` |
| `item_text` | The specific item text | `The president (for presidential system) or Prime Minister (for parliamentary system)` |
| `response_scale` | Response options with codes | `1=A great deal of trust, 2=Quite a lot of trust, 3=Not very much trust, 4=None at all` |
| `notes` | Flags and annotations | `Optional item`, `Wording changed from W5`, `Not included in this wave` |

## Source documents

Read the official questionnaire files for each wave:

| Wave | File | Format |
|------|------|--------|
| Wave 1 | `data/abs/raw/wave1/CoreQs-May25rev.docx` | DOCX |
| Wave 2 | `data/abs/raw/wave2/ABS2_Core Questionnaire20170220.docx` | DOCX |
| Wave 3 | `data/abs/raw/wave3/ABSIII_1_Core Questionnaire.docx` | DOCX |
| Wave 4 | `data/abs/raw/wave4/ABS4_Core_Questionnaire.pdf` | PDF |
| Wave 5 | `data/abs/raw/wave5/ABS5_Core_Questionnaire_20190805.pdf` | PDF |
| Wave 6 | `data/abs/raw/wave6/ABS6_Core_Questionnaire_final.pdf` | PDF |

## Scope — which items to extract

Do NOT extract every question in the questionnaire. Extract only the items that appear in the harmonization YAML configs at:

```
src/config/abs/harmonize_validated/*.yml
```

Cross-reference: for each variable in those YAMLs, look at the `source:` block to get the question ID per wave. Then find that question ID in the questionnaire document and extract the verbatim text.

Example YAML entry (from `institutional_trust.yml`):

```yaml
- id: trust_president
  description: "Trust in president/prime minister"
  source:
    w1:        # not available in W1
    w2: q7
    w3: q7
    w4: q7
    w5: q7
    w6: q7
```

This means: look up q7 in the Wave 2–6 questionnaire documents, and record that Wave 1 has no equivalent item.

## Process

### Step 1: Build the lookup table from YAMLs

Parse all YAML files in `src/config/abs/harmonize_validated/` to build a list of `(harmonized_name, wave, question_id)` tuples. There are roughly 360 variables × 6 waves = ~2,000 entries (minus gaps where items don't exist in a wave). This gives you the complete set of question IDs you need to find per wave.

### Step 2: Extract verbatim text from questionnaire documents

For each wave, read the questionnaire document. For each `question_id` needed for that wave, extract:

- **section**: The section header it falls under (e.g., "B. TRUST IN INSTITUTIONS")
- **stem_text**: The battery introduction, if the item is part of a battery (e.g., q7–q17 all share one stem). Record the stem once per battery; each item row references the same stem.
- **item_text**: The specific item wording (e.g., "The president (for presidential system) or Prime Minister (for parliamentary system)")
- **response_scale**: The full response options with numeric codes (e.g., "1=A great deal of trust, 2=Quite a lot of trust, 3=Not very much trust, 4=None at all")

### Step 3: Handle missing items

Where a `question_id` doesn't exist in a wave (the `source:` value is blank or missing in the YAML), write a row with `item_text = ""` and `notes = "Not included in this wave"`.

### Step 4: Write the CSV

Write to `data/abs/questionnaire_text/abs_verbatim_items.csv`. Sort by `harmonized_name`, then `wave`.

## Integration with existing codebook builder

After creating `abs_verbatim_items.csv`, update `scripts/build_abs_codebook.py` to:

1. Load the verbatim CSV as a lookup table keyed on `(wave, question_id)`
2. Use it as the **primary** source for the `w*_wording` columns in the output codebook (replacing the SPSS label text, which is abbreviated and inconsistent)
3. Fall back to SPSS labels only for items not found in the verbatim file
4. Add a `w*_verbatim` column (or flag) indicating whether the wording came from the official questionnaire or from SPSS labels

## Quality checks

- [ ] Every `(wave, question_id)` pair in the YAML configs should have a matching row in the output CSV (or an explicit "Not included" entry)
- [ ] Battery stems are consistent within a battery (e.g., all q7–q17 share the same trust stem within a given wave)
- [ ] Flag any `question_id` in the YAML that cannot be found in the questionnaire document — these need manual review
- [ ] Spot-check 10–15 high-use items against the PDF to verify exact wording match
- [ ] No interviewer instructions (e.g., "[Do not read]", "(SHOWCARD)") in `item_text` — those belong in `notes` or `response_scale` only

## Practical notes

- The `.docx` files can be read with `python-docx` or converted to text with `markitdown`. The `.pdf` files can be read with `pdfplumber`, `pymupdf`, or `markitdown`.
- **Question numbering shifts across waves.** The YAML `source:` blocks already have the correct per-wave mapping — use those as the ground truth, do not try to infer mappings from question numbers alone.
- Some items have interviewer instructions in brackets (e.g., `[Do not read]`, `(SHOWCARD)`, `<Optional>`) — keep these out of `item_text`. Record `<Optional>` in `notes`.
- Battery stems should be recorded in `stem_text` for each item row (redundant storage is fine for CSV usability — it's easier to query than a normalized schema).
- The Wave 1 questionnaire (`CoreQs-May25rev.docx`) uses a different numbering scheme than later waves. The YAMLs already account for this in their `source: w1:` entries.
- W6 currently has 0 labels loaded in the SPSS label extractor. The verbatim file will fix this gap.

## Why this matters

Every manuscript using ABS data needs an operationalization table (Appendix A) showing exact survey item wording. Currently, each paper session has to dig through PDFs manually. This file makes that a simple CSV lookup: give me the verbatim text for `trust_president` across all waves, or give me every item in the `institutional_trust` concept domain. It also enables automated wording-change detection across waves.
