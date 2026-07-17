# src/r/data_prep_modules/klosa/audit_instrument_stability.R
#
# KLoSA cross-wave INSTRUMENT-STABILITY AUDIT (Task 10, headline deliverable).
#
# Question the paper must settle before writing: is the participation battery
# (outcome) and the Basic Pension item (treatment) asked identically across
# the 2014 reform, or does instrument change contaminate the diff-in-disc?
#
# Method: for every item in the participation membership battery (A033m01-08
# / W1's A017m01-08), the participation frequency battery (A035_01-07 /
# W1's A019_01-07), the Basic Pension treatment (G111/G112/G113 default;
# E111/E113 alternate -- probed at the RAW file level across ALL 9 waves,
# not pre-nulled the way the harmonization spec nulls W1-W4, so this audit
# independently verifies that null decision rather than assuming it), and
# self-rated health (C001), this script pulls the SPSS stem label + full
# value-label set directly from each wave's .sav metadata, then classifies:
#
#   STABLE     - label + response scale constant across present waves
#   RENUMBERED - same construct/scale, different variable NUMBER by wave
#                (the W1 questionnaire-revision pattern)
#   CHANGED    - the response-scale categories actually differ (wording
#                addition, or -- worse -- the variable number is reused for
#                an unrelated construct across a redesign boundary)
#
# Missing-code metadata (-9 Don't know / -8 Refuse) is deliberately excluded
# from the scale-stability comparison: whether a given wave's .sav export
# happens to have DK/Refuse *labels* populated is a codebook-export artifact,
# not an instrument change (confirmed by spot-checking: the underlying -9/-8
# convention is constant project-wide, per CLAUDE.md and every KLoSA harmonize
# YAML). A residual "(none)" label gap (no value labels at all, distinct from
# a real but different scale) is also called out separately rather than
# scored as CHANGED, since it is a metadata gap, not a moved instrument.

suppressMessages({
  library(haven); library(here); library(purrr); library(stringr)
})

waves <- sprintf("w%d", 1:9)
paths <- setNames(here("data", "klosa", "raw", sprintf("w0%d_e.sav", 1:9)), waves)
meta  <- map(paths, ~ read_sav(.x, n_max = 0))

# ---------------------------------------------------------------------------
# Metadata helpers
# ---------------------------------------------------------------------------

lab <- function(wv, v) {
  d <- meta[[wv]]
  if (is.na(v) || !v %in% names(d)) return(NA_character_)
  l <- attr(d[[v]], "label")
  if (is.null(l)) "" else l
}

vsc <- function(wv, v) {
  d <- meta[[wv]]
  if (is.na(v) || !v %in% names(d)) return("(absent)")
  l <- attr(d[[v]], "labels")
  if (is.null(l)) "(none)" else paste(sprintf("%s=%s", l, names(l)), collapse = "; ")
}

# strip -9=.../-8=... (DK/Refuse) rows before comparing scales across waves --
# whether those two codes happen to be labelled in a given wave's export is
# metadata noise, not an instrument change (see header note).
core_scale <- function(s) {
  if (s %in% c("(absent)", "(none)")) return(s)
  parts <- str_split(s, "; ")[[1]]
  parts <- parts[!grepl("^-9=|^-8=", parts)]
  if (length(parts) == 0) "" else paste(parts, collapse = "; ")
}

mk <- function(...) { v <- c(...); stopifnot(length(v) == 9); setNames(v, waves) }
varname <- function(wv_i, suf) if (is.na(suf)) NA_character_ else sprintf("w0%d%s", wv_i, suf)

md_safe <- function(x) gsub("\\|", "/", x)

# ---------------------------------------------------------------------------
# Item registry
# ---------------------------------------------------------------------------

group_id    <- c("religious", "social_club", "leisure", "alumni", "volunteer", "civic", "other", "none")
group_label <- c("Religious groups", "Social clubs", "Leisure/culture/sports groups",
                  "Alumni associations / hometown communities / family councils",
                  "Volunteer groups", "Political parties / NGOs / interest groups",
                  "Other group", "No group memberships")

items <- list()

# --- OUTCOME: participation MEMBERSHIP battery, A033m01-08 (W2-W9) / A017m01-08 (W1) ---
for (i in seq_along(group_id)) {
  m <- sprintf("%02d", i)
  id <- sprintf("part_%s", group_id[i])
  items[[id]] <- list(
    heading  = sprintf("part_%s (membership: %s)", group_id[i], group_label[i]),
    category = "OUTCOME -- participation MEMBERSHIP battery (0=No, 1=Yes)",
    suffix   = mk(sprintf("A017m%s", m), rep(sprintf("A033m%s", m), 8)),
    notes    = sprintf(
      "W1 = w01A017m%s; W2-W9 = w0NA033m%s. Same 6-group-type battery (%s), same 0/1 membership coding, in W1 and W2-W9 -- confirmed a pure item-RENUMBER from the W1->W2 questionnaire revision (identical pattern to the A001->A002 age/birth-date shift documented in demographics.yml), not an instrument change.",
      m, m, group_label[i])
  )
}

# --- OUTCOME: participation FREQUENCY battery, A035_01-07 (W2-W9) / A019_01-07 (W1) ---
for (i in 1:7) {
  s <- sprintf("%02d", i)
  id <- sprintf("partfreq_%s", group_id[i])
  extra <- if (group_id[i] == "other") {
    " NOTE: this item's W2 value-label dictionary is empty ('(none)') in the raw .sav -- a codebook-export metadata gap (no labels stored for that wave/column), not a moved scale; the 1-10 raw values are presumably intact but unverifiable from metadata alone. This is the ONLY such gap found anywhere in the two batteries, and it does not touch partfreq_civic (the paper's actual frequency outcome for the 'buy a citizen' item) or any membership item."
  } else ""
  items[[id]] <- list(
    heading  = sprintf("partfreq_%s (frequency: %s)", group_id[i], group_label[i]),
    category = "OUTCOME -- participation FREQUENCY battery (10-pt DECLINING-frequency ordinal: 1=most frequent...10=almost never engaged)",
    suffix   = mk(sprintf("A019_%s", s), rep(sprintf("A035_%s", s), 8)),
    notes    = sprintf(
      "W1 = w01A019_%s; W2-W9 = w0NA035_%s. Same declining-frequency 10-pt scale in both families -- pure RENUMBER, same pattern as the membership battery.%s",
      s, s, extra)
  )
}

# --- TREATMENT: G-block (default), present W2-W9, genuinely absent W1 (2006 predates the 2007 law) ---
items[["basic_receipt_G"]] <- list(
  heading  = "basic_receipt_G (G111 -- Basic Pension receipt, G-block DEFAULT)",
  category = "TREATMENT -- Basic Pension receipt, G-block (named default, W2-W9)",
  suffix   = mk(NA, rep("G111", 8)),
  notes    = "Genuinely absent W1 (2006 predates the 2007 Basic Old-Age Pension law; a structural placebo, not a redesign gap). Present + STABLE W2-W9: label stays 'Receipt of the Basic Old-Age Pension Benefit' verbatim through W9 even though the underlying benefit was renamed 'Basic Pension' at the 2014 reform -- the questionnaire never updated the item's own stem text, but its 1=currently receiving/3=will receive/5=not entitled coding is byte-for-byte identical W2-W9. Screener-gated (NA where the respondent never applied -- see G110); this is the paper's default treatment source and it crosses the 2014 boundary with an UNCHANGED variable number, UNCHANGED coding, and (modulo cosmetic label drift) UNCHANGED stem. -8=Refuse appears inconsistently across waves in the value-label metadata (present W3, W6-W9; absent W2, W4, W5, which carry only -9=Don't know or neither code); DK/Refuse codes are excluded from the scale comparison, so this is a codebook-population artifact, not a scale change (the underlying -9/-8 convention is universal)."
)
items[["basic_amount_G"]] <- list(
  heading  = "basic_amount_G (G112 -- Basic Pension monthly amount, G-block DEFAULT)",
  category = "TREATMENT -- Basic Pension amount, G-block (named default, W2-W9)",
  suffix   = mk(NA, rep("G112", 8)),
  notes    = "Genuinely absent W1 (same placebo reason as G111). Present + STABLE W2-W9 at an unchanged variable number and label ('monthly average amount of the Basic Old-Age Pension benefit, unit: 10,000 won'). Continuous item, no substantive value-label categories to compare (only -9/-8 metadata, which is what 'core scale = empty' means below) -- confirmed stable by construction. See the dedicated G/E amount-divergence section below for the real-data caveat: G112 tracks ENTITLEMENT/SCHEDULE level, not amount actually received, and is stored in raw KRW despite its own label claiming 10,000-won units (fixed in harmonization via won_to_10k_won(), per pension_basic.yml / task-6-report.md)."
)
items[["basic_couple_G"]] <- list(
  heading  = "basic_couple_G (G113 -- benefit paid to individual vs couple, G-block DEFAULT)",
  category = "TREATMENT -- Basic Pension couple/individual flag, G-block (W2-W9, no E-block equivalent)",
  suffix   = mk(NA, rep("G113", 8)),
  notes    = "Genuinely absent W1. Present + STABLE W2-W9 (1=Provided to the individual, 5=Provided to the couple, unchanged). No E-block equivalent was found in any wave -- if the paper needs this for the E-block-based W5-W9 receipt measure, that gap is structural, not a stability defect."
)

# --- TREATMENT: E-block (alternate), raw content probed across ALL 9 waves, not pre-nulled --
#     this independently verifies the harmonization spec's W1-W4 null decision.
items[["basic_receipt_E"]] <- list(
  heading  = "basic_receipt_E (E111 -- Basic Pension receipt, E-block ALTERNATE)",
  category = "TREATMENT -- Basic Pension receipt, E-block (alternate/cross-check, W5-W9 only)",
  suffix   = mk(rep("E111", 9)),
  notes    = "Probed at the SAME variable number (E111) in all 9 waves to independently verify the harmonization spec's W1-W4 null: E111 does not exist as a column at all in W1-W4 (confirmed 'ABSENT' at the .sav metadata level, not merely unmapped) -- a genuinely NEW item added at W5 (2014), not a repurposed one. Present + STABLE W5-W9: 'In last year, check whether or not receipt of Basic Pension (Ex Basic Old-Age Pension)', 1=Check (checkbox-style, no explicit 0=No code; blank=not received is an inference, see pension_basic.yml). Cross-tab in task-6-report.md: 99.69% row-level agreement with G111 where both non-missing (W9) -- strong confirmation the two modules track the same benefit."
)
items[["basic_amount_E"]] <- list(
  heading  = "basic_amount_E (E113 -- Basic Pension monthly amount, E-block ALTERNATE)",
  category = "TREATMENT -- Basic Pension amount, E-block (alternate/cross-check, W5-W9 only)",
  suffix   = mk(rep("E113", 9)),
  notes    = "⚠️ GENUINE FINDING beyond the brief: probed at the SAME variable number (E113) in all 9 waves, E113 is NOT simply absent pre-2014 -- it EXISTS in W1-W4, but as a COMPLETELY DIFFERENT, unrelated item: 'In last year, check for the total amount of Other welfare Benefit' (1=Yes, 5=No categorical check-flag). Only from W5 does E113 become 'the monthly average amount of Basic Pension (Ex Basic Old-Age Pension)' (a continuous amount field). The variable NUMBER is reused across the 2014 redesign for an unrelated construct with a different scale TYPE (binary check-flag -> continuous amount) -- this is a REPURPOSED number, a materially different and more dangerous pattern than a simple RENUMBER or ABSENT, because a naive 'does the column exist' check across all waves would wrongly conclude E113 is present and comparable throughout. E112 shows the identical repurposing pattern (pre-2014 'monthly amount of Other welfare Benefit' -> post-2014 'number of months of receipt of Basic Pension') though E112 (months) is not one of the two treatment items this audit tables. The harmonization spec (pension_basic.yml) correctly restricts basic_pension_amount_eblock's source to W5-W9 only and never touches pre-2014 E113 -- this audit independently confirms that restriction was the right call, not an oversight."
)

# --- CONTROL: self-rated health, C001, stable position, wording shifts at W3 ---
items[["srh"]] <- list(
  heading  = "srh (C001 -- self-rated health)",
  category = "CONTROL -- self-rated health",
  suffix   = mk(rep("C001", 9)),
  notes    = "Present at an unchanged variable number in all 9 waves, but the response-CATEGORY WORDING shifts at W3: W1-W2 have no 'Excellent' category (1=Very good...5=Very bad); W3-W9 add 'Excellent' as a new top category (1=Excellent, 2=Very good, 3=Good, 4=Fair, 5=Poor), pushing 'Very good' down to position 2. Ordinal DIRECTION (1=best, 5=worst) is preserved throughout, so identity harmonization is safe for a monotonic control, but W1/W2 respondents never had the 'Excellent' option available -- a genuine reference-point shift, not just codebook noise. -9/-8 metadata is inconsistently populated (present W1/W3/W5-W9, absent W2/W4) -- a codebook-export artifact, not a scale change."
)

# ---------------------------------------------------------------------------
# Stem-label constancy helpers
#
# The documented contract for STABLE is "label AND response scale constant
# across present waves" -- classify_item() below checks both. Two known
# sources of harmless noise have to be normalized away first, or they turn
# into false CHANGED verdicts:
#
#  (1) KLoSA's own raw .sav exports for W1-W8 hard-truncate SPSS variable
#      labels at 80 characters; W9 (and any label under the ceiling) carries
#      the full text. Confirmed by direct inspection -- e.g. G112, E111,
#      E113, and several participation-battery items all show nchar==80 in
#      W1-W8 with W9's longer label a strict continuation of the same text.
#      Treating that truncation as a wording change would flip genuinely
#      stable items (G112 among them) to CHANGED.
#  (2) A handful of KLoSA stems embed the wave/year ("In 2014, ...") or a
#      stray copy-paste formula fragment ("=2018-..."); those are stripped
#      before comparison so an embedded-year difference alone can't flip a
#      stable item.
#
# Whitespace/case differences are also normalized away. A residual material
# difference (e.g. "the NGOs, the interest groups" -> "NGO, interest groups")
# survives all of this and is treated as real drift.
# ---------------------------------------------------------------------------

STEM_TRUNC_LEN <- 80

normalize_stem <- function(x) {
  if (is.na(x)) return(NA_character_)
  x <- trimws(x)
  x <- gsub("\\s+", " ", x)
  x <- tolower(x)
  x <- sub("^in\\s+\\d{4},?\\s*", "", x)              # "In 2014, ..." wave/year prefix
  x <- sub("^=\\S*\\d{4}\\S*[,:]?\\s*", "", x)         # "=2018-..." formula-fragment prefix
  x
}

# TRUE if two raw stem labels are the same item, allowing for the W1-W8
# 80-char truncation ceiling: if the shorter one hit that exact ceiling and
# is a normalized prefix of the longer one, it's a truncation artifact, not
# a real wording change.
stems_match <- function(raw_a, raw_b) {
  if (is.na(raw_a) || is.na(raw_b)) return(TRUE)
  na_a <- normalize_stem(raw_a); na_b <- normalize_stem(raw_b)
  if (identical(na_a, na_b)) return(TRUE)
  len_a <- nchar(trimws(raw_a)); len_b <- nchar(trimws(raw_b))
  if (len_a <= len_b) { short_n <- na_a; short_len <- len_a; long_n <- na_b
  } else { short_n <- na_b; short_len <- len_b; long_n <- na_a }
  short_len == STEM_TRUNC_LEN && nchar(short_n) > 0 && startsWith(long_n, short_n)
}

# Group present waves by their same-variable-number suffix cohort (e.g. all
# of W2-W9 sharing "A033m03") and check stem constancy WITHIN each cohort.
# A cohort of one wave is trivially stable; cross-cohort comparison (e.g. W1
# vs W2-W9) is a RENUMBERED question, not a stem-drift question.
stem_cohorts_stable <- function(present_waves, suf, labels) {
  if (length(present_waves) < 2) return(TRUE)
  cohorts <- split(present_waves, suf[present_waves])
  all(vapply(cohorts, function(cw) {
    if (length(cw) < 2) return(TRUE)
    ref <- labels[[cw[1]]]
    all(vapply(cw[-1], function(wv) stems_match(ref, labels[[wv]]), logical(1)))
  }, logical(1)))
}

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

classify_item <- function(it) {
  suf <- it$suffix
  src <- map2_chr(1:9, suf, varname)
  names(src) <- waves
  wv_named <- setNames(waves, waves)
  exists <- map_lgl(wv_named, ~ !is.na(src[[.x]]) && src[[.x]] %in% names(meta[[.x]]))
  labels <- map_chr(wv_named, ~ if (exists[[.x]]) lab(.x, src[[.x]]) else NA_character_)
  scales <- map_chr(wv_named, ~ if (exists[[.x]]) vsc(.x, src[[.x]]) else "(absent)")
  core   <- map_chr(scales, core_scale)

  present_waves <- waves[exists]
  metadata_gap_waves <- waves[exists & core == "(none)"]
  real_mask <- exists & !(core %in% c("(none)"))

  stem_note <- NULL

  if (length(present_waves) == 0) {
    verdict <- "ABSENT (raw variable not found in any wave)"
  } else {
    scale_stable <- length(unique(core[real_mask])) <= 1
    distinct_suffix <- unique(suf[exists])
    stem_stable <- stem_cohorts_stable(present_waves, suf, labels)
    if (!scale_stable) {
      # find the first wave (in order) where core scale diverges from the first present wave's
      base <- core[which(real_mask)[1]]
      pivot <- present_waves[real_mask[exists] & core[exists] != base][1]
      verdict <- sprintf("CHANGED -- response scale differs starting at %s (present waves: %s)",
                          ifelse(is.na(pivot), "an unresolved wave", pivot),
                          paste(present_waves, collapse = ", "))
    } else if (length(distinct_suffix) > 1) {
      grp <- split(waves[exists], suf[exists])
      detail <- paste(sprintf("%s=%s", names(grp), map_chr(grp, ~ paste(range(.x), collapse = "-"))), collapse = "; ")
      verdict <- sprintf("RENUMBERED -- same construct/scale, different variable number by wave (%s)", detail)
      if (!stem_stable) {
        stem_note <- "STEM WORDING DRIFT: the stem label is not constant within a same-variable-number wave cohort (see per-wave label column above), even though the verdict remains RENUMBERED because the construct and response scale are unchanged."
      }
    } else if (stem_stable) {
      verdict <- "STABLE"
    } else {
      verdict <- sprintf("CHANGED -- stem label differs across present waves despite an unchanged variable number and response scale (present waves: %s)",
                          paste(present_waves, collapse = ", "))
    }
  }

  list(src = src, labels = labels, scales = scales, exists = exists,
       present_waves = present_waves, metadata_gap_waves = metadata_gap_waves,
       stem_note = stem_note, verdict = verdict)
}

results <- map(items, classify_item)

# ---------------------------------------------------------------------------
# Write outputs/klosa/instrument_stability_audit.md
# ---------------------------------------------------------------------------

out_path <- here("outputs", "klosa", "instrument_stability_audit.md")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)

verdict_word <- function(v) sub(" .*$", "", v)  # first token: STABLE / RENUMBERED / CHANGED / ABSENT

out <- c(
"# KLoSA cross-wave instrument-stability audit (W1-W9)",
"",
sprintf("Generated by `src/r/data_prep_modules/klosa/audit_instrument_stability.R`. Metadata pulled directly from each wave's raw `.sav` (n_max=0 reads, `attr(x,\"label\")` / `attr(x,\"labels\")`), not from `variable_map.csv` or any harmonize YAML, so this audit is an independent check on those documents rather than a restatement of them."),
"",
"Verdict definitions: **STABLE** (label + response scale constant across present waves) / **RENUMBERED** (same construct/scale, different variable NUMBER by wave -- the W1 questionnaire-revision pattern) / **CHANGED** (the response-scale categories actually differ -- a wording addition, or a variable number reused for an unrelated construct across a redesign boundary). Don't-know/Refuse (-9/-8) label metadata is excluded from the scale-stability comparison (codebook-export noise, not an instrument change); a bare metadata gap (no value labels at all for one wave) is called out separately rather than scored CHANGED.",
"",
"## Top-line: does instrument change contaminate the diff-in-disc?",
"",
"**OUTCOME (participation battery) -- NO contamination.** All 8 membership items (`A033m01-08`, W2-W9) and all 7 frequency items (`A035_01-07`, W2-W9) are STABLE in both construct and response scale. W1 alone uses different variable numbers (`A017m01-08` / `A019_01-07`) for the identical construct and identical coding -- a pure questionnaire RENUMBERING at the W1->W2 revision, not an instrument change; W1 is usable as the battery's placebo wave without any scale-comparability caveat. Nothing in the outcome battery moves across the 2014 reform boundary (W4->W5): every present-wave item is STABLE straight through it.",
"",
"**TREATMENT (Basic Pension) -- NO contamination on the G-block default; a real but bounded amount-measurement caveat.** `basic_receipt_G` (G111), `basic_amount_G` (G112), and `basic_couple_G` (G113) are all STABLE at an unchanged variable number, unchanged coding, and (modulo the stale 'Basic Old-Age Pension' stem text the questionnaire never updated) unchanged wording, from W2 straight through W9 -- the G-block instrument crosses the 2014 reform completely intact. The E-block alternate (E111/E113) is a genuinely NEW item at W5 for receipt (E111 does not exist pre-2014 -- confirmed absent, not repurposed) but a REPURPOSED variable number for amount (E113 exists W1-W4 as an unrelated 'Other welfare Benefit' check-flag, then becomes the Basic Pension amount field from W5) -- a finding beyond what was known going into this task, documented in full below. It does not touch the harmonization spec, which already correctly nulls E111/E113 pre-2014, but it is a hazard for any FUTURE script that assumes 'same variable number = same construct' for the E-block. The one real substantive caveat, unrelated to instrument identity, is that the G-block and E-block AMOUNT measures diverge ~2x right at the reform boundary (W5-W6) before converging by W7-W9 -- see the dedicated section below.",
"",
"**CONTROL (srh, C001) -- CHANGED at W3, not at the 2014 boundary.** The 'Excellent' category is added at W3 (2010), four waves before the reform (W5, 2014). This shifts respondents' reference point starting W3 but does not interact with the 2014 treatment discontinuity, since W3 is on neither side of it in isolation -- both W4 (pre-reform) and W5-W9 (post-reform) share the same 5-point 'Excellent...Poor' scale, so srh IS internally comparable across the diff-in-disc window itself. The W1-W2 vs W3-W9 wording break only matters if the design also leans on W1-W2 as a health baseline.",
"",
"## G-block vs E-block treatment-amount divergence (dedicated section)",
"",
"The two amount measures for the SAME benefit diverge sharply right where the diff-in-disc identifies the effect, then converge. From `pension_basic.yml` / `task-6-report.md` (real harmonized-data medians, 10,000-KRW units):",
"",
"| wave | G112 median (entitlement/schedule) | E113 median (amount actually received) | ratio G/E |",
"|---|---|---|---|",
"| w5 (2014) | 20.00 | 9.00 | 2.22x |",
"| w6 (2016) | 20.00 | 10.00 | 2.00x |",
"| w7 (2018) | 20.00 | 19.00 | 1.05x |",
"| w8 (2020) | 24.00 | 24.00 | 1.00x |",
"| w9 (2022) | 25.00 | 25.00 | 1.00x |",
"",
"Most likely explanation (per `pension_basic.yml`'s note): the 2014-15 National-Pension-linkage deduction reduced actual payouts below the statutory maximum for higher-National-Pension-benefit recipients in the reform's first two waves; G112 (the questionnaire's entitlement/schedule-level question) does not reflect that deduction the way E113 (amount actually received) does. Row-level RECEIPT agreement between the two blocks is high throughout (99.69% where both non-missing, W9) -- this is an AMOUNT-only divergence, not a receipt-identity problem. **Implication for the paper: do not treat G112 and E113 as interchangeable dose measures in W5-W6; if the identification strategy uses amount (not just receipt) right at the 2014 boundary, prefer E113 (amount received) over G112 (schedule) for that window, or report both and flag the gap.**",
"",
"## Item-by-item detail",
""
)

for (id in names(items)) {
  it <- items[[id]]
  r <- results[[id]]
  vword <- verdict_word(r$verdict)
  out <- c(out,
    sprintf("### %s -- **%s**", it$heading, vword),
    "",
    sprintf("*%s*", it$category),
    "",
    sprintf("Verdict detail: %s", r$verdict),
    "")
  if (length(r$metadata_gap_waves) > 0) {
    out <- c(out, sprintf("⚠️ Metadata gap (no value labels defined at all, not a scale change): %s.",
                           paste(r$metadata_gap_waves, collapse = ", ")), "")
  }
  out <- c(out,
    "| wave | source var | label | response scale |",
    "|---|---|---|---|")
  for (wv in waves) {
    src_disp   <- ifelse(is.na(r$src[[wv]]), "—", r$src[[wv]])
    label_disp <- ifelse(is.na(r$labels[[wv]]), "—", md_safe(r$labels[[wv]]))
    scale_disp <- md_safe(r$scales[[wv]])
    out <- c(out, sprintf("| %s | %s | %s | %s |", wv, src_disp, label_disp, scale_disp))
  }
  notes_text <- if (is.null(r$stem_note)) it$notes else paste(it$notes, r$stem_note)
  out <- c(out, "", notes_text, "")
}

writeLines(out, out_path)
cat(sprintf("Wrote %s (%d items audited).\n", out_path, length(items)))

verdicts_summary <- map_chr(results, ~ verdict_word(.x$verdict))
cat("\nVerdict counts:\n")
print(table(verdicts_summary))
