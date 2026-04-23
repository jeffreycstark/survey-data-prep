---
name: appendix-variable-builder
description: Build and maintain Appendix A (variable descriptions) for academic survey research papers. Use this skill when the user asks to create, update, audit, or rebuild a variable descriptions appendix for any paper in the paper-bank. Also trigger when the user mentions "Appendix A", "variable table", "question wording", "codebook", "survey items used", or wants to document which survey questions map to which analysis variables. Works backwards from .qmd manuscript and appendix files to identify all variables referenced, then builds a structured appendix section with question wording, response scales, transformations, and coding notes. Prefers rich prose format (full question wording) over compact tables. Especially useful after adding new variables to analysis or when preparing a paper for journal submission.
---

# Appendix Variable Builder

This skill builds and maintains the "Appendix A: Variable Descriptions" section of online appendices for survey-based academic papers. It works backwards from the manuscript and appendix `.qmd` files to identify all variables used, then generates structured documentation with full question wording.

## Master Codebook Infrastructure

The ground truth for variable-to-survey-question mappings lives in the `survey-data-prep` repo:

### Source of truth: Harmonization YAMLs
```
/Users/jeffreystark/Development/Research/survey-data-prep/
  src/config/abs/harmonize_validated/*.yml   # One YAML per concept domain
```

Each YAML contains:
- `id`: Harmonized variable name (e.g., `trust_military`)
- `description`: Near-verbatim question content
- `source`: Raw question number per wave (e.g., `w1: q012, w2: q13, ...`)
- `scale`: Min, max, and value labels
- `harmonize`: Method and exceptions per wave (reversals, 6pt-to-4pt, etc.)
- `note`: Wave-specific caveats

### Master codebook CSV
```
/Users/jeffreystark/Development/Research/survey-data-prep/
  data/processed/abs_variable_codebook.csv
```

Built by `scripts/build_abs_codebook.py`. Columns:
- `harmonized_name`, `concept`, `yaml_file`, `description`, `type`
- `scale_min`, `scale_max`, `scale_labels`
- `w1_source` through `w6_source` (raw question numbers per wave)
- `w1_wording` through `w6_wording` (exact text from questionnaire label files)
- `harmonize_default`, `harmonize_exceptions`, `notes`

**If the CSV does not exist yet**, tell the user to run:
```bash
cd /Users/jeffreystark/Development/Research/survey-data-prep
python scripts/build_abs_codebook.py
```

### Wave label files (exact question wording)
```
/Users/jeffreystark/Development/Research/survey-data-prep/
  data/abs/labels/W1_labels.txt through W5_labels.txt
```

These contain the literal questionnaire text per variable per wave. The codebook script pulls wording from these automatically.

**CRITICAL**: Question numbers shift across ABS waves (e.g., W1 `q012` = trust in military, but W1 `q130` = "our form of government is best" while W5 `q130` = placement on democracy scale). The harmonization YAMLs handle this mapping. Never assume a question number means the same thing across waves.

## Workflow

### Step 1: Identify the paper and its variables

Read the manuscript `.qmd` and appendix `.qmd` using Filesystem tools. Extract all variable names from:
- R code chunks (model formulas, data manipulation)
- Inline R expressions
- Existing variable tables (tribble/tibble definitions)
- Prose references to variables

Also check the paper's `00_data_preparation.R` for the definitive `vars_to_select` list.

Papers live at:
```
/Users/jeffreystark/Development/Research/paper-bank/papers/XX_paper_name/
```

### Step 2: Look up each variable in the master codebook

Read the codebook CSV. For each variable used in the paper:
1. Find the matching `harmonized_name` row
2. Extract the description, scale, source questions, and wordings
3. Note any wave-specific caveats

For **derived variables** (composites, indices, recoded variables), these will not be in the codebook. Document their construction formula based on the `00_data_preparation.R` script and note which source variables they combine.

### Step 3: Generate Rich Prose Format

The preferred output format is **rich prose with full question wording**, following the pattern established in paper 01b (Information Trust). Structure:

```markdown
# Appendix A: Survey Question Wording

This appendix documents the exact wording of all Asian Barometer Survey items
used in the analysis. Question numbers vary across ABS waves; the source
column in each entry lists the raw question ID for each wave included in
the analysis. All items were harmonized to a common scale direction as
described below.

## Dependent Variables

**Trust in Military** (`trust_military`)

*Source:* ABS W1: q012; W2-W6: q13

*Question:* "How much trust do you have in [the military]?"

*Response options:* (1) None at all; (2) Not very much trust;
(3) Quite a lot of trust; (4) A great deal of trust

*Harmonization:* W1-W2 identity; W3-W4, W6 reversed (raw: 1=great deal,
4=none); W5 mapped from 6-point to 4-point scale.

*Coding:* Higher values indicate greater trust. Scale: 1-4.

---
```

Key formatting rules:
- Group variables by role: Dependent, Primary Independent, Controls, Derived/Composite
- Include source question numbers for ALL waves used by the paper (not just one wave)
- Note harmonization method if non-trivial (reversals, scale compression)
- For derived variables, show the construction formula
- Use `---` separators between categories
- Bold the display name, put the harmonized variable name in backticks

### Step 4: Handle paper-specific transformations

The master codebook documents what the variable *is* in the ABS. But papers may use variables in specific ways that differ from the general description. For example:
- A paper might reverse-code a variable relative to the harmonized direction
- A paper might use only a subset of waves
- A paper might construct a composite from several codebook variables

When generating the appendix, note any paper-specific transformations on top of the harmonized baseline. The `00_data_preparation.R` script in each paper is the authority for paper-specific transformations.

### Step 5: Audit Mode

When the user says "audit" or "check":
1. Parse manuscript + appendix for all variable references
2. Load the existing Appendix A content
3. Compare and report:
   - **Missing**: Variables in analysis but not in Appendix A
   - **Orphaned**: Variables in Appendix A but not referenced in manuscript
   - **Stale**: Variables where the description does not match the codebook

## Non-ABS Surveys

For papers using other surveys (WVS, Afrobarometer, LAPOP, KGSS, KAMOS, LBS):
- Check `survey-data-prep/src/config/{survey}/harmonize_validated/` for equivalent YAMLs
- The codebook script currently only covers ABS; extending it to other surveys follows the same pattern
- If no YAML exists, ask the user for the codebook or question numbers

## Paper-Bank Conventions

- Model template: `papers/00-model/manuscript/PAPER-online-appendix.qmd`
- Data config: `paper-bank/_data_config.R` (paths to harmonized datasets)
- Rich format example: `papers/01b-information_trust_vietnam/manuscript/it-online-appendix.qmd`
- Compact format example: `papers/05_thailand_trust_collapse/manuscript/tt-online-appendix.qmd`

## Important Reminders

- **Never fabricate question wording.** If the codebook CSV or label file does not have the exact text, flag it as `[TODO: verify wording against ABS questionnaire]`.
- **The YAML `description` field is close but not always verbatim.** Prefer `w*_wording` from the label files when available.
- **Question numbers are NOT stable across waves.** Always report per-wave source IDs.
- **Use Filesystem tools** to read files on the user's computer. Claude's computer filesystem (bash/view) is separate.
