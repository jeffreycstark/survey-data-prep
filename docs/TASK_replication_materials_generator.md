# Replication materials — derivation transcript generator

**Status:** Planning / not yet built.
**Drafted:** 2026-05-13.
**Trigger:** Submitting replication materials for papers that use harmonized survey data, when the harmonization engine itself is IP-private.

---

## The problem

For each paper that ships replication materials:

- The harmonized `.rds` is in the replication set (data behind the paper — must be there).
- The paper-side R analysis script is in the replication set (already handled by the existing replication-package skill).
- **Missing:** something that shows how each harmonized variable was derived from the raw survey codes.

The harmonization engine (`src/r/harmonize/`, `src/r/utils/recoding.R`, the YAML schema, the audit framework) is IP and stays private. But reviewers need transparency on the raw → harmonized mapping for every variable the paper uses.

The unit to ship is **a per-paper derivation transcript** bounded to the variables that actually appear in the paper's analysis. NOT the universal pipeline.

---

## What reviewers actually need (per variable used)

1. Which raw variable in which raw file (e.g. `q100` in `Wave1_20170906.sav`).
2. The question text exactly as asked.
3. The raw code labels (e.g. `1 = Very satisfied … 4 = Very dissatisfied`).
4. Which codes were treated as missing.
5. Whether/how codes were recoded, reversed, collapsed, or derived.
6. Any wave-specific exceptions.

What they do NOT need: the orchestration engine, the audit framework, the cross-survey scale registry, or the harmonization for variables your paper doesn't use.

---

## Spectrum of options

### Option 1 — Ship .rds + point to this repo
Minimal. Doesn't satisfy DA-RT-style standards. **Reject.**

### Option 2 — Ship .rds + the relevant YAML files
Cheapest. IP-honest (YAML is declarations, not engine). But `fn: safe_reverse_4pt` is opaque without context, and reviewers can't run anything from YAML alone. **Documentation-grade, not replication-grade.**

### Option 3 — Ship .rds + YAML + a redacted `recoding.R` containing only the functions the paper's variables use
Better — named functions become inspectable. But you're exposing implementations of `safe_reverse_*`, `collapse_*`, the country-conditional recodes, etc. Those ARE part of your IP investment. **Bleeds.**

### Option 4 — Ship .rds + a hand-written derivation document
Full transparency, zero engine exposure. Cost: 2-4 hours per paper depending on variable count. Doesn't scale across ~10 papers. Drift risk: document silently disagrees with what was actually run. **Workable for 1-2 papers; doesn't scale.**

### Option 5 — Ship .rds + an auto-generated per-paper derivation document ⭐ RECOMMENDED

A generator script (lives in your private engine repo, stays private) consumes:

- A paper's variable list (extracted from the paper's R script, or supplied manually)
- The YAML specs (`src/config/<survey>/harmonize/...`)
- The verbatim CSVs (`data/<survey>/questionnaire_text/...`)
- The recoding registry (`src/r/utils/recoding_registry.yml`)
- The extracted codebooks (`data/<survey>/codebook/<wave>.parquet`)
- The manifest for the harmonized output (`outputs/<survey>/manifest.json`)

Emits one markdown (or PDF / docx) file per paper. The **output** goes in the replication package; the **generator** stays in the engine repo.

### Option 6 — Option 5 plus a self-contained "frozen replication script"
Generator additionally produces an R script that takes raw `.sav` as input and produces the harmonized columns inline — no YAML, no engine, no `recoding.R` dependency. Each variable's transformation hand-translated into inline `case_when` or `recode` calls.

**Pros over Option 5:** machine-verifiable replication. Reviewer can run the script and reproduce the .rds bit-for-bit.

**Cons:** substantially more generator complexity (must compile YAML rules + function bodies into inline R), and arguably overshoots what most journals require.

**Use only for hard-replication journals (AJPS, ICPSR deposits).** For most journals, Option 5 + the .rds + the manifest hash is enough.

---

## Recommended deliverable shape (Option 5)

```markdown
# Replication materials — Paper [N] derivation transcript

Generated: 2026-MM-DD
Harmonized data: abs_harmonized.rds (sha256: ...)
Harmonization run: manifest.json (sha256: ...)

## dem_country_present_govt

Harmonized scale: 1 (Complete dictatorship) → 10 (Complete democracy)
Type: continuous (W1 raw permits half-step responses)

| Wave | Raw var | Question text                                          | Raw scale         | Missing codes (→NA)       | Transformation |
|------|---------|--------------------------------------------------------|-------------------|---------------------------|----------------|
| W1   | q100    | "Where would you place our country under the present   | 1-10 thermometer  | -1, 0, 97, 98, 99         | identity       |
|      |         | government?"                                           |                   |                           |                |
| W2   | q96     | (same)                                                 | 1-10 thermometer  | -1, 0, 97, 98, 99         | identity       |
| ...  | ...     | ...                                                    | ...               | ...                       | ...            |

## gov_sat_national

Harmonized scale: 1 (Very dissatisfied) → 4 (Very satisfied)
Type: ordinal

| Wave | Raw var | Question text                                | Raw scale                                  | Missing codes (→NA)     | Transformation |
|------|---------|----------------------------------------------|--------------------------------------------|-------------------------|----------------|
| W1   | q104    | "Satisfaction with the central government?"  | 5-point with 5=Half/Half middle category   | -1, 0, 7, 8, 9          | Collapse middle (5) to NA, then reverse so high=satisfied |
| W2   | q99     | (same)                                       | 1=Very satisfied → 4=Very dissatisfied     | -1, 0, 7, 8, 9, 97, 98, 99 | Reversed: harmonized = 5 − raw for raw ∈ {1..4}; otherwise NA |
| ...  | ...     | ...                                          | ...                                        | ...                     | ...            |
```

For more complex cases the **Transformation** cell becomes prose:

- **Reversal:** *"Raw 1=Very satisfied → 4=Very dissatisfied; reversed so harmonized 4 = most satisfied. Implementation: harmonized = 5 − raw for raw ∈ {1,2,3,4}; raw ∈ {-1,0,7,8,9,97,98,99} → NA."*
- **Derived variables:** *"Computed from q85-q88 as a 0-4 count of procedural-democracy choices: each item scored 1 if respondent chose the procedural option (e.g. q85 ∈ {2,4}), 0 if substantive (q85 ∈ {1,3}), summed across 4 items."*
- **Country-conditional:** *"Vietnam (country=11) used a reversed coding in W2 raw; corrected here so all 12 country slices are in standard direction. Other countries: identity passthrough."*
- **Scale collapse:** *"W5 raw is 5-point (1=save_a_lot through 5=great_difficulties). Collapsed and reversed: raw {1,2} → harmonized 4 (covers well); raw 3 → 3; raw 4 → 2; raw 5 → 1."*

Reviewer gets full transparency on raw → harmonized mapping for every variable in the paper. Engine, audit framework, registry, YAML schema all stay private.

---

## What the generator already has to work from

| Input | Where | What it gives |
|---|---|---|
| YAML harmonization spec | `src/config/<survey>/harmonize/<concept>.yml` | source mapping per wave, missing-code convention, harmonize method + fn name, scale.labels, per-wave exceptions |
| Verbatim CSV | `data/<survey>/questionnaire_text/<survey>_verbatim_items.csv` | per-wave question text + raw response scale text |
| Recoding registry | `src/r/utils/recoding_registry.yml` | per-function: reverses? monotonic? requires_data? input/output scale, prose `notes` field |
| Extracted codebook | `data/<survey>/codebook/<wave>.parquet` | per-wave raw codes + labels + missing-code flag (.sav-derived) |
| Run manifest | `outputs/<survey>/manifest.json` | sha256 hashes of inputs/specs/outputs at harmonization time — provenance for the .rds shipped |

All five exist already. Generator is glue.

---

## Edge cases to handle

1. **Country-conditional recodes** (e.g. `reverse_trust_vietnam_w2`): the recoding registry's `notes:` field should describe the condition. Generator translates to prose.
2. **Derived variables** (e.g. `compute_procedural_index`): the registry's `notes` covers it; YAML's `derive` method + `sources:` list the input columns.
3. **Wave-specific exceptions** (e.g. `dem_extent_current` W1=null because no equivalent question, or `hh_income_sat` per-wave collapse functions): the per-wave table already handles this — one row per wave.
4. **Variables with no `qc.validate.phrase`**: question text must come from the verbatim CSV; if missing, generator should fail loud rather than silently emit "?".
5. **Sister variables sourcing the same raw column** (e.g. `dem_satisfaction` + `dem_country_not_democracy` both source AFRO `q40`): both appear in the transcript; reviewer sees that one raw question produced two harmonized columns.
6. **R10 stacking (AFRO)**: for surveys whose raw input is a stack of per-country files, the `raw_file` cell should list the stacking method or point to the build script.

---

## Build effort

- **Generator core:** ~6-10 hours. Ingests the five inputs above, walks each variable in the paper's variable list, emits the markdown table per variable.
- **Polishing the recoding registry's `notes:` fields:** ~30 min one-time pass. Some are terse (sufficient for transformation logic but not always pretty as prose). Polishing once improves every paper's transcript thereafter.
- **Per-paper invocation:** ~30 seconds. Generator reads the paper's R script, extracts harmonized-variable names via regex (or accepts an explicit list), produces `replication/derivation_transcript.md`.

Total to be paper-submission-ready for all ~10 papers: ~10 hours upfront + 30 sec per paper.

---

## Practical CLI sketch

```bash
# Auto-detect variables from paper's R script
Rscript src/r/replication/build_derivation_transcript.R \
  --paper paper-bank/papers/03_cambodia_fairy_tale/analysis/main.R \
  --survey abs \
  --output paper-bank/papers/03_cambodia_fairy_tale/replication/derivation_transcript.md

# Or: explicit variable list
Rscript src/r/replication/build_derivation_transcript.R \
  --vars dem_sat_national,gov_sat_national,dem_country_future,dem_country_present_govt \
  --survey abs \
  --output /tmp/transcript.md

# Multi-survey (paper uses ABS + KGSS)
Rscript src/r/replication/build_derivation_transcript.R \
  --vars-by-survey 'abs:dem_sat_national,gov_sat_national;kgss:conf_president' \
  --output /tmp/transcript.md
```

---

## Decision points for when you come back to this

1. **Build the generator now, or hand-write transcripts for the next 1-2 papers and then evaluate?** Hand-writing first lets you discover what reviewers actually want before locking in a template. Generator is a 10-hour investment best made once the template is settled.

2. **Markdown only, or also docx / PDF output?** Some journals prefer PDF. Pandoc handles the conversion cleanly from markdown — probably markdown-first, pandoc post-step if needed.

3. **Should the transcript include observed-marginal statistics per variable per wave?** (e.g. "W2: n=24,301, % missing=2.1%, marginal: 12% / 28% / 38% / 22%"). Adds reviewer-useful context but bloats the document. Probably optional via `--include-marginals` flag.

4. **Where does the generator live in the repo?** Suggested: `src/r/replication/build_derivation_transcript.R`, with output template at `src/r/replication/_template_derivation.md`. Keeps it grouped with other replication-related tooling and out of the audit framework.

5. **Should Option 6 (self-contained R replication script) be a sibling output of the same generator, or a separate tool?** Same generator with a `--emit-script` flag is cleaner. But it's deferred — only build when a journal demands it.

---

## Status when you come back

Nothing built yet. The infrastructure inputs (YAML, verbatim CSV, recoding registry, extracted codebooks, manifests) are all already in place from the audit work. The generator itself does not exist.

Next concrete action when you return: decide between (a) hand-write a transcript for one paper first to settle the template, or (b) build the generator straight-away.
