# three-source-triptych — side-by-side codebook / YAML / raw-label cards

**Purpose**: print the three authorities on every survey item — the parsed
**codebook**, the **YAML harmonize spec**, and the **raw file's embedded
labels** — side by side, aligned by response code, so a human can validate the
harmonization by eye (on screen or on paper). This is the *manual* complement
to the automated gates: Check A decides polarity, the collision checker decides
convention overlaps; this skill shows you everything and lets you judge.

## Usage

```bash
cd ~/Development/Research/survey-data-prep

# full survey (one HTML page per spec file + index.html)
Rscript scripts/three-source-triptych/render_triptych.R --survey abs

# volume controls — combine freely
Rscript scripts/three-source-triptych/render_triptych.R --survey abs \
  --spec democracy.yml            # one spec file
Rscript scripts/three-source-triptych/render_triptych.R --survey abs \
  --var dem_country_future        # one harmonized variable
Rscript scripts/three-source-triptych/render_triptych.R --survey abs \
  --wave w4                       # one wave
Rscript scripts/three-source-triptych/render_triptych.R --survey abs \
  --disagreements-only            # only FLAGGED cards — the triage pack
  --out outputs/triptych/abs-triage   # keep it separate from the full render
```

Output: `outputs/triptych/<survey>/` (gitignored). Open `index.html`; each
page prints cleanly (print CSS: one card never splits across pages), so the
paper workflow is open → Cmd-P.

## Reading a card

One card per **variable × wave** (waves with a non-null `source:` only).
Header: harmonized id, wave, source variable, method/fn, valid_range, resolved
missing codes (convention + `missing.codes` + `qc.treat_as_na`), the codebook
question text and the raw variable label. Below it, one row per response code:

| mark | meaning |
|---|---|
| `OK` (green) | all compared sources agree (normalized; prefix-tolerant, so abbreviations pass) |
| `≈` (yellow) | codebook and raw agree; the YAML wording diverges — usually paraphrase, occasionally a direction bug. Worth a glance; does **not** flag the card |
| `DIFF` (red) | **codebook and raw contradict each other** — flags the card |
| `M` (grey) | code is treated as missing by the spec |
| `M!` (orange) | treated as missing, but the codebook's `missing_code_flag` is FALSE — the convention-collision signature; flags the card |
| `—` | code absent in that source (neutral) |
| purple italic YAML cell | non-identity wave: the YAML column describes the *harmonized* target scale and is deliberately **not compared** to the raw wave |

Cards also carry badges (all flag the card):

- red **Check A** — `audit/reports/<survey>/04-label-reconciliation.csv` has an
  `error` row for this variable × wave: the polarity check the dumb text
  comparison cannot do (paraphrase vs. opposite). Run the audit first.
- purple **Check D** — bin-width `parity_error`: this wave's harmonized bins
  hold a different number of native categories than its siblings (pole-merge /
  collapse seams).
- orange **ARITY** — the raw wave's substantive code set (contiguous run) has a
  different size than the harmonized target scale's span: the format-seam
  signature (e.g. a Yes/No wave fed through a 4-pt transform, or a 5-category
  wave identity-mapped onto a 6-category scale). Exempt: explicit `recode`
  mappings and nominal-under-transform (deliberate collapses); non-contiguous
  label sets (endpoint-labelled 0–10 scales) don't fire.

`--disagreements-only` keeps only flagged cards (DIFF, M!, or Check A error).
ABS full render: ~1,170 cards / ~115 flagged, i.e. the triage pack is ~10% of
the volume. Whole-survey render takes ~5 s.

## Sources per survey

| column | ABS source |
|---|---|
| CODEBOOK | `data/abs/codebook/w1..w6.parquet` (long: raw_var × response_code, with `missing_code_flag`) |
| YAML | `src/config/abs/harmonize/*.yml` |
| RAW | haven label attrs from `data/processed/w1..w6.rds` (same route Check A uses) |

**ABS only for now.** To add a survey, extend `.SURVEYS` in
`render_triptych.R` with three fields: `spec_dir`, `waves`, `codebook()`
(return a data frame with `raw_var`, `wave`, `question_text`, `response_code`,
`response_label`, `missing_code_flag` — for surveys without a parsed codebook,
adapt the verbatim dictionary CSV or `questionnaire_parsed` parquet), and
`raw_labels(wave)` (return `list(<lowercased var> = list(var_label, val_labels))`;
crib the survey's entry in `.SURVEY_LABEL_LOADER` in
`src/r/audit/04_label_reconciliation.R`).

## Caveats

- The comparison is *textual*. Identical wording with opposite numeric coding
  passes text comparison — that's what the Check A badge is for.
- For `method: recode` / `r_function` waves the YAML column is informational
  only; validating the *transform* itself is Check A / strict-reversal
  territory.
- `MODEL_VARIABLE.yml` is the template and renders too; ignore it or delete it
  from the spec dir.
