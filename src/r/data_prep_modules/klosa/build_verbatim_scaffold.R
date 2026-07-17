# src/r/data_prep_modules/klosa/build_verbatim_scaffold.R
#
# KLoSA VERBATIM QUESTION DICTIONARY scaffold (Task 11).
#
# Builds data/klosa/questionnaire_text/klosa_verbatim_items.csv in the
# repo-standard 8-column format (CLAUDE.md "Verbatim Question Dictionary",
# matches data/abs/questionnaire_text/abs_verbatim_items.csv column-for-
# column): wave, question_id, harmonized_name, section, stem_text,
# item_text, response_scale, notes. One row per harmonized_name x wave
# (43 harmonized variables x 9 waves = 387 rows), INCLUDING waves where a
# variable is absent (per CLAUDE.md: "include rows where variable is
# absent").
#
# We do NOT have the official KLoSA questionnaire booklets (PDF/HWP) on
# disk, so per the repo's fallback convention this is a SCAFFOLD: item_text
# is the raw SPSS variable LABEL (pulled directly from each wave's .sav
# metadata via n_max=0 reads, the same method as
# audit_instrument_stability.R) and response_scale is the raw SPSS
# value-label set for that same wave/variable -- NOT the harmonized target
# scale. Every substantive (mapped) row is flagged in `notes` that verbatim
# backfill from the official questionnaire is still pending (see
# docs/surveys/klosa.md).
#
# Harmonized-variable resolution is read directly from the 8 production
# YAML specs (src/config/klosa/harmonize/*.yml) via yaml::read_yaml() --
# NOT hand-copied -- so this script stays correct if a spec's source
# mapping ever changes. The two exceptions are adl_count/iadl_count, which
# are `method: derive` over an 8-/9-item raw battery (C201-C208 /
# C209-C217) rather than a single raw column; those are expanded to the
# full battery range below instead of using the YAML's single-column
# placeholder source.
#
# Key harmonization findings (Task 2/4/5/6/7/10) are carried into `notes`
# on the affected variables: the G-block screener/denominator caveat on
# basic_pension_receipt, the G/E amount ~2x divergence near the 2014
# reform, the E-block absence (E111, genuinely new) vs. repurposing (E113,
# a different item pre-2014) distinction, the participation W1 renumber
# (A017m/A019_ -> A033m/A035_) plus the 3 cosmetic stem-wording-drift items
# (part_leisure, part_civic, partfreq_leisure), the srh W3 wording shift,
# and the income/pension unit notes (E126->E147 relocation, G112's
# won_to_10k_won unit fix).

suppressMessages({
  library(haven)
  library(here)
  library(yaml)
  library(purrr)
  library(readr)
})

waves    <- sprintf("w%d", 1:9)
wave_num <- setNames(1:9, waves)

# ---------------------------------------------------------------------------
# Raw .sav metadata (n_max = 0 -- labels/value-labels only, no row data)
# ---------------------------------------------------------------------------

sav_paths <- setNames(
  here("data", "klosa", "raw", sprintf("w0%d_e.sav", 1:9)),
  waves
)
meta <- map(sav_paths, ~ read_sav(.x, n_max = 0))

lab <- function(wv, v) {
  if (is.null(v) || is.na(v)) return(NA_character_)
  d <- meta[[wv]]
  if (!v %in% names(d)) return(NA_character_)
  l <- attr(d[[v]], "label")
  if (is.null(l)) "" else l
}

vsc <- function(wv, v) {
  if (is.null(v) || is.na(v)) return(NA_character_)
  d <- meta[[wv]]
  if (!v %in% names(d)) return(NA_character_)
  l <- attr(d[[v]], "labels")
  if (is.null(l) || length(l) == 0) "" else paste(sprintf("%s=%s", l, names(l)), collapse = "; ")
}

# ---------------------------------------------------------------------------
# Registry: harmonized variables resolved from the 8 production YAML specs
# ---------------------------------------------------------------------------

`%||%` <- function(a, b) if (is.null(a)) b else a

spec_files <- sort(list.files(here("src", "config", "klosa", "harmonize"),
                               pattern = "\\.yml$", full.names = TRUE))
specs <- map(spec_files, yaml::read_yaml)

registry <- list()
for (sp in specs) {
  for (v in sp$variables) {
    registry[[v$id]] <- list(
      id           = v$id,
      concept      = v$concept %||% "",
      source       = v$source,
      scale_labels = v$scale$labels
    )
  }
}

stopifnot(length(registry) == 43)  # 8 specs, 43 harmonized variables (per Task 8 runner report)

format_scale_labels <- function(labels) {
  if (is.null(labels) || length(labels) == 0) return("")
  paste(sprintf("%s=%s", names(labels), unlist(labels)), collapse = ", ")
}

# ---------------------------------------------------------------------------
# Battery stems (participation membership/frequency, ADL/IADL) -- blank for
# every non-battery (single-item) variable
# ---------------------------------------------------------------------------

STEM_PART_MEMBER <- paste(
  "Battery: membership in each of several group types (religious groups;",
  "social clubs [e.g. private savings club, senior citizens' club];",
  "leisure/culture/sports groups [e.g. class for the elderly]; alumni",
  "associations/hometown communities/family councils; volunteer groups;",
  "political parties/NGOs/interest groups; no group) -- 0=No, 1=Yes for",
  "each type. Parallel items: part_religious, part_social_club,",
  "part_leisure, part_alumni, part_volunteer, part_civic, part_none."
)

STEM_PART_FREQ <- paste(
  "Battery: for each group type reported as a membership (see the part_*",
  "battery), frequency of participation on a 10-point DECLINING-frequency",
  "ordinal (1=almost every day [most frequent] ... 10=almost never engaged",
  "[least frequent]). Parallel items: partfreq_religious,",
  "partfreq_social_club, partfreq_leisure, partfreq_alumni,",
  "partfreq_volunteer, partfreq_civic."
)

STEM_ADL <- paste(
  "Battery (C201-C208): whether help is required for 8 activities of daily",
  "living -- dressing; washing face/hair/brushing teeth; bathing/showering;",
  "eating; getting in/out of bed and walking; using the toilet; using the",
  "toilet without spilling; grooming. Raw coding is non-linear: 1=No help",
  "needed, 3=Need help to some extent, 5=Need help in every respect (NOT a",
  "plain 1/2/3 ladder). adl_count is a DERIVED count of items >=3 across",
  "this battery (klosa_adl_count(), src/r/utils/recoding.R), not itself a",
  "single raw item."
)

STEM_IADL <- paste(
  "Battery (C209-C217): whether help is required for 9 instrumental",
  "activities of daily living -- household chores; preparing meals;",
  "laundry; near-distance going out; going out using transportation;",
  "shopping; managing money; making/taking a phone call; taking",
  "medications. Same non-linear 1=No help needed / 3=Need help to some",
  "extent / 5=Need help in every respect coding as the ADL battery.",
  "iadl_count is a DERIVED count of items >=3 across this battery",
  "(klosa_iadl_count(), src/r/utils/recoding.R), not itself a single raw",
  "item."
)

stem_for <- function(id) {
  if (id %in% c("adl_count")) return(STEM_ADL)
  if (id %in% c("iadl_count")) return(STEM_IADL)
  if (startsWith(id, "partfreq_")) return(STEM_PART_FREQ)
  if (startsWith(id, "part_")) return(STEM_PART_MEMBER)
  ""
}

# ---------------------------------------------------------------------------
# Per-variable caveats (mapped waves) and absent-wave extras (unmapped
# waves), carrying forward the key Task 2/4/5/6/7/10 findings
# ---------------------------------------------------------------------------

BACKFILL_NOTE <- "item_text from SPSS label; verbatim backfill from official questionnaire pending."

PART_RENUMBER_NOTE <- paste(
  "W1 column is in the A017m/A019_ family; W2-W9 use the A033m/A035_",
  "family -- pure item RENUMBERING at the W1->W2 questionnaire revision",
  "(same pattern as the A001->A002 age/birth-date shift in",
  "demographics.yml), confirmed identical construct/coding across the",
  "boundary; NOT an instrument change. W1 is usable as this battery's",
  "placebo wave without a scale-comparability caveat."
)

CAVEATS <- list(
  part_leisure = paste(
    PART_RENUMBER_NOTE,
    "STEM WORDING DRIFT: the stem label is not byte-identical within the",
    "W2-W9 cohort (e.g. 'Leisure/culture/sports related group' vs",
    "'Leisure/cultural/sports related groups'), but the verdict stays",
    "RENUMBERED, not CHANGED -- construct and 0/1 coding are unchanged."
  ),
  part_civic = paste(
    PART_RENUMBER_NOTE,
    "STEM WORDING DRIFT: the stem label drifts within the W2-W9 cohort",
    "('the NGOs, the interest groups' vs 'NGO, interest groups'), but",
    "construct and 0/1 coding are unchanged (RENUMBERED, not CHANGED).",
    "This is the paper's narrow civic-participation ('buy a citizen')",
    "outcome."
  ),
  partfreq_leisure = paste(
    PART_RENUMBER_NOTE,
    "STEM WORDING DRIFT: same drift pattern as part_leisure; construct and",
    "the 10-pt declining-frequency coding are unchanged (RENUMBERED, not",
    "CHANGED)."
  ),

  basic_pension_receipt = paste(
    "G-block DEFAULT (G111).",
    "⚠ SCREENER/DENOMINATOR CAVEAT: G111 is asked only of respondents",
    "who applied for the benefit, so its NA is a SKIP (did not apply), not",
    "a refusal -- mean(x, na.rm=TRUE) over this column is CONDITIONAL ON",
    "APPLICATION (~92%), not a population receipt rate. A population-rate",
    "reading requires treating skip as 0 (paper-side choice; document it,",
    "cf. src/r/lookups/kipa_bribery_series.R's denominator pattern).",
    "Cross-check: agrees ~92-99.69% with the E-block alternate",
    "(basic_pension_receipt_eblock) where both are non-missing, W5-W9."
  ),
  basic_pension_receipt_eblock = paste(
    "E-block ALTERNATE (E111), W5-W9 only. Checkbox item: 1=Check",
    "(received, paired 1:1 with non-NA E113 amount); blank/NA = inferred",
    "not-received (true item-nonresponse is indistinguishable from a",
    "genuine 'no' under this convention). Genuinely NEW item added at the",
    "2014 reform -- confirmed ABSENT (not repurposed) in W1-W4 at the raw",
    ".sav level."
  ),
  basic_pension_amount = paste(
    "G-block DEFAULT (G112), the entitlement/schedule-level amount.",
    "⚠ UNIT FIX: raw stored values are the literal KRW amount rounded",
    "to the nearest 10,000 (NOT already divided by 10,000, despite the",
    "SPSS label's own '10,000 won' claim) -- harmonized via",
    "won_to_10k_won().",
    "⚠ G/E DIVERGENCE NEAR THE 2014 REFORM: diverges ~2x from the",
    "E-block actual-amount-received measure (basic_pension_amount_eblock)",
    "in W5-W6 (median 20 vs 9-10, 10k-won units), converging by W7-W9 --",
    "most likely the 2014-15 National-Pension-linkage deduction. Do not",
    "treat G112 and E113 as interchangeable dose measures right at the",
    "reform boundary."
  ),
  basic_pension_amount_eblock = paste(
    "E-block ALTERNATE (E113), the amount actually received, W5-W9 only.",
    "⚠ E113 IS A REPURPOSED VARIABLE NUMBER pre-2014: in W1-W4, E113",
    "exists but as a completely different, unrelated item ('In last year,",
    "check for the total amount of Other welfare Benefit', a 1=Yes/5=No",
    "check-flag) -- NOT simply absent. Only from W5 does E113 become the",
    "Basic Pension amount field.",
    "⚠ G/E DIVERGENCE NEAR THE 2014 REFORM: diverges ~2x from the",
    "G-block schedule-level amount (basic_pension_amount) in W5-W6,",
    "converging by W7-W9 -- see basic_pension_amount."
  ),
  basic_pension_couple = paste(
    "G-block only (G113); no E-block 'self or couple' equivalent exists in",
    "any wave."
  ),

  hh_income_total = paste(
    "THIRD relocation instance in this survey (after the pension G->E",
    "block and the birth-date A001->A002 anchor shift): W1-W4 source is",
    "E126, W5-W9 is E147. Real-data median check confirms the relocation",
    "is low-risk -- same order of magnitude across the boundary (W4 E126",
    "median=2,000; W5 E147 median=2,000, 10,000-KRW units). Units verified",
    "stable throughout (~12M-25M KRW/year, plausible for KLoSA's 45+",
    "retiree-heavy panel); no unit conversion needed."
  ),
  assets_total = paste(
    "Units verified (Task 7): medians run ~130M-270M KRW, the expected",
    "order of magnitude for Korean household net worth. No unit",
    "conversion needed."
  ),
  assets_realestate = paste(
    "Present + stable across all 9 waves, but with a much smaller",
    "non-missing n than assets_total in every wave -- consistent with a",
    "genuine skip pattern (asked only of households reporting real-estate",
    "holdings), not item nonresponse. Units verified (~100M-200M KRW); no",
    "unit conversion needed."
  ),

  srh = paste(
    "⚠ INSTRUMENT-STABILITY: response-category WORDING shifts",
    "starting W3. W1-W2 = 1=Very good...5=Very bad (no 'Excellent' top",
    "category). W3-W9 = 1=Excellent,2=Very good,3=Good,4=Fair,5=Poor (adds",
    "'Excellent', pushing 'Very good' to position 2). Ordinal DIRECTION",
    "(1=best,5=worst) is unchanged, so identity harmonization is",
    "monotonic-safe, but W1/W2 respondents never had the 'Excellent'",
    "option -- a genuine reference-point shift, not just codebook noise."
  ),

  sex = paste(
    "Raw KLoSA coding is 1=Male, 5=Female; recoded to the project-standard",
    "1/2 in harmonization (this dictionary's response_scale column reports",
    "the RAW scale, not the harmonized one)."
  ),
  birth_year = paste(
    "W1 column is in the A001 family (w01A001y); W2-W9 use the A002",
    "family (w0NA002y) -- a genuine per-wave item renumbering, confirmed",
    "identical coding across the boundary."
  ),
  birth_month = paste(
    "Same A001->A002 renumbering pattern as birth_year. Confirmed 100%",
    "populated in all 9 waves (spot-checked W1/W4/W9) -- contradicts an",
    "earlier design-time assumption that no birth-month item existed;",
    "enables a finer age-in-months RD running variable."
  ),
  age = paste(
    "Same A001->A002 renumbering pattern as birth_year. The SPSS variable",
    "LABEL text itself has cosmetic copy-paste bugs in W6/W7/W9 (wrong",
    "wave/year references in the label's stated formula) -- the label",
    "text shown here reproduces that bug verbatim; the underlying stored",
    "age VALUES are correct (spot-checked = interview_year - birth_year",
    "in 100% of rows)."
  ),
  marital_status = paste(
    "W1 column is w01A006 ('Currently marital status'); W2-W9 use",
    "w0Nmarital ('In <year>, the current marital status') -- coding",
    "confirmed identical across the renumbering."
  ),
  hhid = paste(
    "W1-W8 column is lowercase 'hhid'; W9 uses UPPERCASE 'HHID' -- same",
    "construct, case difference only. Do not confuse with W9's separate,",
    "unrelated 'HHID22' column."
  ),
  weight = paste(
    "wgt_c (cross-sectional weight). UNRESOLVED CAVEAT: the 'Horizontal",
    "weighting'/'Vertical weighting' value-label semantics attached to",
    "wgt_c vs. the companion wgt_p column appear to SWAP at W8-W9 relative",
    "to W1-W7 in the raw metadata -- does not affect which column IS",
    "wgt_c (confirmed present and stably named all 9 waves), but do not",
    "trust the cross-sectional/panel label semantics for W8-W9 without the",
    "official KLoSA user guide."
  ),
  iw_month = paste(
    "W6 column (w06mniw_m) is stored as a zero-padded CHARACTER string",
    "(SPSS format A2), unlike the numeric storage in every other wave --",
    "routed through r_function no_verify in harmonization so the QC range",
    "check compares numbers, not lexicographic strings."
  ),
  iw_day = paste(
    "Same W6 character-storage quirk as iw_month (w06mniw_d is SPSS",
    "format A2) -- routed through r_function no_verify for W6 only."
  ),

  natl_pension_receipt = paste(
    "E033 is a 4-category item (1=only monthly benefit, 2=only lump-sum,",
    "3=received both, 4=no); harmonized 'received any' = {1,2,3}->1,",
    "4->0. Age-linked CONTRIBUTORY pension -- a confound, distinct from",
    "the non-contributory Basic Pension treatment in pension_basic.yml."
  ),

  work_status = paste(
    "D001 ('Currently work'); raw coding 1=Yes/5=No. Two label-similar",
    "items (D006 job-seeking-willingness ladder; D009 prior-wave",
    "carry-forward recheck) were investigated and rejected as candidates",
    "-- see variable_map.csv."
  )
)

ABSENT_EXTRA <- list(
  basic_pension_receipt = paste(
    "W1 (2006) predates the 2007 Basic Old-Age Pension law -- a genuine",
    "structural placebo, not a redesign gap."
  ),
  basic_pension_amount = "Same placebo reason as basic_pension_receipt (predates the 2007 law).",
  basic_pension_couple = "Same placebo reason as basic_pension_receipt.",
  basic_pension_receipt_eblock = paste(
    "E111 does not exist as a column at all pre-2014 (confirmed ABSENT at",
    "the .sav metadata level, not merely unmapped) -- a genuinely NEW item",
    "added at the 2014 reform, not a repurposed one."
  ),
  basic_pension_amount_eblock = paste(
    "⚠ E113 is NOT simply absent here -- the raw column EXISTS",
    "pre-2014 but as a completely different, unrelated item ('In last",
    "year, check for the total amount of Other welfare Benefit', a",
    "1=Yes/5=No check-flag), repurposed to the Basic Pension amount field",
    "only from W5. This harmonized variable is correctly left unmapped",
    "for W1-W4 (the repurposed pre-2014 column is a different construct),",
    "but a naive 'does E113 exist' check would wrongly conclude",
    "otherwise."
  ),
  assets_total = "Confirmed genuinely missing from the raw W1 file, not a naming variant."
)

part_note_for <- function(id) {
  if (id %in% names(CAVEATS)) return(CAVEATS[[id]])
  if (startsWith(id, "part_") || startsWith(id, "partfreq_")) return(PART_RENUMBER_NOTE)
  NULL
}

# ---------------------------------------------------------------------------
# Row builder
# ---------------------------------------------------------------------------

ADL_SUFFIXES  <- sprintf("C%03d", 201:208)
IADL_SUFFIXES <- sprintf("C%03d", 209:217)

build_battery_row <- function(id, concept, wave, suffixes) {
  wn <- wave_num[[wave]]
  battery_vars <- sprintf("w0%d%s", wn, suffixes)
  stopifnot(all(battery_vars %in% names(meta[[wave]])))  # STABLE per health.yml/Task 7 -- fail loudly if not

  question_id <- sprintf("%s-%s", battery_vars[1], battery_vars[length(battery_vars)])
  item_text   <- paste(map_chr(battery_vars, ~ lab(wave, .x)), collapse = "; ")
  scales      <- map_chr(battery_vars, ~ vsc(wave, .x))
  response_scale <- scales[1]
  if (length(unique(scales)) > 1) {
    warning(sprintf("%s %s: battery value-labels are not uniform across items -- using %s's scale",
                     id, wave, battery_vars[1]))
  }

  caveat <- part_note_for(id)
  notes  <- if (is.null(caveat)) BACKFILL_NOTE else paste(caveat, BACKFILL_NOTE)

  tibble_row(wave, question_id, id, concept, stem_for(id), item_text, response_scale, notes)
}

build_single_row <- function(id, concept, wave, raw_var, scale_labels) {
  stem <- stem_for(id)
  if (is.null(raw_var)) {
    response_scale <- format_scale_labels(scale_labels)
    extra <- ABSENT_EXTRA[[id]]
    notes <- if (is.null(extra)) "Not included in this wave" else paste0("Not included in this wave. ", extra)
    return(tibble_row(wave, "", id, concept, stem, "", response_scale, notes))
  }

  item_text      <- lab(wave, raw_var)
  response_scale <- vsc(wave, raw_var)
  if (is.na(item_text) || is.na(response_scale)) {
    stop(sprintf("%s %s: source var '%s' declared in spec but not found in raw .sav -- registry/data mismatch", id, wave, raw_var))
  }

  caveat <- part_note_for(id)
  notes  <- if (is.null(caveat)) BACKFILL_NOTE else paste(caveat, BACKFILL_NOTE)

  tibble_row(wave, raw_var, id, concept, stem, item_text, response_scale, notes)
}

tibble_row <- function(wave, question_id, harmonized_name, section, stem_text, item_text, response_scale, notes) {
  data.frame(
    wave = wave, question_id = question_id, harmonized_name = harmonized_name,
    section = section, stem_text = stem_text, item_text = item_text,
    response_scale = response_scale, notes = notes,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# Assemble
# ---------------------------------------------------------------------------

rows <- list()
for (id in names(registry)) {
  reg <- registry[[id]]
  for (wave in waves) {
    if (id %in% c("adl_count", "iadl_count")) {
      suf <- if (id == "adl_count") ADL_SUFFIXES else IADL_SUFFIXES
      rows[[length(rows) + 1]] <- build_battery_row(id, reg$concept, wave, suf)
    } else {
      rows[[length(rows) + 1]] <- build_single_row(id, reg$concept, wave, reg$source[[wave]], reg$scale_labels)
    }
  }
}

out <- do.call(rbind, rows)
stopifnot(ncol(out) == 8)
stopifnot(nrow(out) == 43 * 9)

out_path <- here("data", "klosa", "questionnaire_text", "klosa_verbatim_items.csv")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
readr::write_csv(out, out_path, na = "")

cat(sprintf("Wrote %s (%d rows, %d harmonized variables x %d waves, %d cols).\n",
            out_path, nrow(out), length(registry), length(waves), ncol(out)))
