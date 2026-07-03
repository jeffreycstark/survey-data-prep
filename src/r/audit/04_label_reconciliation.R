#!/usr/bin/env Rscript
# src/r/audit/04_label_reconciliation.R
#
# Layer 4 — Label-reconciliation check (audit ticket D5; the "wrong-fn" detector).
#
# Catches the failure mode that the strict-reversal check (04_strict_reversal.R)
# and the transformation invariant (validation.R) are blind to: a variable whose
# recoding function RAN CLEANLY but was the WRONG function, so the stored data
# points the OPPOSITE direction from its own documented scale.labels.
#
# This is exactly how two ABS bugs shipped (system_deserves_support and the
# dem_* democracy-supply battery, both 2026-06-20): raw value labels put the
# positive pole at code 1 ("Strongly agree"), the spec's scale.labels declared
# the positive pole at code 4 ("Strongly agree"), and the chosen fn was a
# non-reversing safe_4pt_none — so the harmonized output stored every respondent
# backwards relative to its labels. It passed range/type/completeness/reversal-
# fidelity because safe_4pt_none did its (identity) job perfectly.
#
# Mechanism (deterministic, no correlations, no external construct):
#   1. RAW direction  : classify the raw .sav value labels into poles and find
#                       which END (low/high code) holds the positive pole.
#   2. REALIZED output: apply the declared fn's direction (reverses? from the
#                       recoding registry) to that end. A monotone non-reversing
#                       fn preserves the end; a reversing fn flips it.
#   3. DECLARED output: classify the spec's scale.labels and find which end the
#                       positive pole is declared to sit at.
#   4. COMPARE        : realized end must equal declared end. Mismatch => ERROR.
#
# Ground truth for the RAW side is the .sav value labels — NOT the verbatim
# question dictionary, whose response_scale records the INTENDED (post-harmonize)
# direction and would have endorsed the bug.
#
# Division of labor (state explicitly):
#   strict-reversal      = "did the fn run cleanly?"   (mechanical fidelity)
#   label-reconciliation = "was choosing that fn correct?" (direction correctness)
# Together they close the loop for every monotone, label-bearing variable.
#
# Public API:
#   classify_pole(label_text, lexicon)        -- pure pole classifier
#   find_pole_end(labels_named, lexicon)      -- "low" | "high" | NA + detail
#   reconcile_one(...)                         -- one (var, wave) row (testable)
#   compute_label_reconciliation(survey, ...)  -- tibble for a survey
#   run_label_reconciliation(survey, ...)      -- write CSV + summary
#
# CLI:
#   Rscript src/r/audit/04_label_reconciliation.R --survey abs
#   Rscript src/r/audit/04_label_reconciliation.R --all-surveys
#
# Status meanings:
#   ok    — realized output direction matches declared scale.labels
#   error — realized output direction CONTRADICTS declared labels (bug)
#   skip  — cannot anchor (no raw labels / no declared labels / ambiguous /
#           non-reversible fn / nominal / unknown fn). Always carries a reason.
#
# Exit code 0 if no errors; 1 if any error rows present.
#
# v2 (Phase 4, 2026-07-03): all surveys with a label loader; bilingual EN+KO
# lexicon (Korean patterns are written to be disjoint from their negated forms
# — 만족 vs 불만족 via lookbehind, 동의(?!하지) — so the pos&neg→unknown rule
# still protects midpoints like "neither agree nor disagree"); declared-side
# fallback to the verbatim dictionary's response_scale when the spec has no
# scale.labels (declared_source=verbatim_response_scale; gated to surveys
# whose dictionary verifiably documents the intended direction — see
# .VERBATIM_DECLARED_SURVEYS); and method=recode
# reconciled by pushing the raw pole codes through the literal mapping
# (mirroring harmonize.R: unmapped/null → NA).
#
# POLE CONVENTION ACROSS LANGUAGES: a family's pos/neg assignment must agree
# between its EN and KO patterns (많다 ↔ "a lot" both pos), because the raw
# side may classify in Korean while the declared side classifies in English.
# What matters is per-family consistency, not normative valence.
#
# See audit/01-audit-framework.md §Layer 4 and the plan at
#   ~/.claude/plans/so-how-do-i-glowing-meteor.md

suppressPackageStartupMessages({
  library(yaml)
  library(here)
  library(haven)
  library(dplyr)
  library(tibble)
})

`%||%` <- function(a, b) if (!is.null(a)) a else b

# Reuse the engine-mirroring resolver (.resolve_wave_rule) from the strict-
# reversal script so the two Layer-4 checks resolve wave rules identically.
if (!exists(".resolve_wave_rule", mode = "function")) {
  source(here::here("src", "r", "audit", "04_strict_reversal.R"))
}


# ===========================================================================
# Polarity lexicon (English, Phase 1). Each family lists positive-pole and
# negative-pole regex patterns. Word boundaries keep "disagree" out of
# "\\bagree\\b". Patterns match the EXTREMES and the bare poles; that is
# sufficient to establish which end of a monotone scale is positive.
# ===========================================================================
default_polarity_lexicon <- function() {
  # NOTE on Korean patterns: PCRE \b is unreliable at Hangul boundaries, so
  # KO patterns use plain substrings with lookarounds to stay disjoint from
  # negated forms ("만족" must not fire inside "불만족"). Negated Korean forms
  # conveniently change the final syllable ("그렇다" never occurs inside
  # "그렇지 않다"), which keeps most families disjoint without lookarounds.
  list(
    agree     = list(pos = c("\\bagree\\b", "(?<!그저 )그렇다", "그런 편",  # 그저 그렇다 = "so-so" midpoint
                             "동의(?!\\s?하지)", "찬성"),
                     neg = c("\\bdisagree\\b", "그렇지 않", "동의하지 않",
                             "동의\\s?하지\\s?않", "반대")),
    satisfied = list(pos = c("\\bsatisfied\\b", "\\bsatisfaction\\b",
                             "(?<!불)만족"),
                     neg = c("\\bdissatisfied\\b", "not.*satisfied",
                             "불만족", "만족하지 않")),
    trust     = list(pos = c("great deal", "\\ba lot\\b", "quite a lot",
                             "trust.*completely", "\\bfully trust",
                             "신뢰(?!\\s?하지)", "믿는다", "믿는 편"),
                     neg = c("not at all", "none at all", "no trust",
                             "do not trust", "don'?t trust", "not very much",
                             "hardly any",
                             "신뢰하지 않", "불신", "믿지 않")),
    amount    = list(pos = c("a great deal", "\\ba lot\\b", "very much",
                             "\\bgood deal\\b", "great extent",
                             "매우 많", "많은 편", "많다"),
                     neg = c("not at all", "\\bnone\\b", "very little",
                             "\\bnot much\\b", "hardly any", "limited extent",
                             "전혀 없", "별로 없", "거의 없", "없다",
                             "적다", "적은 편")),
    everyone  = list(pos = c("\\beveryone\\b", "\\ball of them\\b"),
                     neg = c("\\bno one\\b", "\\bnobody\\b")),
    essential = list(pos = c("(?<!not )very essential"),
                     neg = c("not essential", "not very essential")),
    necessary = list(pos = c("(?<!not )very necessary",
                             "(?<!불)필요(?!\\s?(하지|없))"),
                     neg = c("not.*necessary", "unnecessary",
                             "필요\\s?하지 않", "필요\\s?없", "불필요")),
    threat    = list(pos = c("(?<!not )very threatened",
                             "(?<!not )threatened(?! at all)"),
                     neg = c("not threatened", "no threat")),
    want      = list(pos = c("strongly wants?", "(?<!not )wants?\\b"),
                     neg = c("does not want", "not want", "원하지 않")),
    strength  = list(pos = c("very strong", "\\bstrong\\b",   # \b excludes "strongly (dis)agree"
                             "강하", "강력"),
                     neg = c("very weak", "\\bweak\\b", "약하")),
    quality   = list(pos = c("very good", "\\bgood\\b", "much better",
                             "\\bbetter\\b", "좋다", "좋은", "좋아"),
                     neg = c("very bad", "\\bbad\\b", "much worse",
                             "\\bworse\\b", "나쁘", "나빠", "좋지 않")),
    proud     = list(pos = c("\\bproud\\b", "자랑스럽(?!지)", "자랑스러"),
                     neg = c("\\bashamed\\b", "not.*proud",
                             "자랑스럽지", "부끄럽")),
    frequency = list(pos = c("\\balways\\b", "\\boften\\b", "frequently",
                             "항상", "자주", "언제나"),
                     neg = c("\\bnever\\b", "\\brarely\\b", "\\bseldom\\b",
                             "전혀\\s?(없|안|않|못)", "거의\\s?(없|안|않)",
                             "드물게")),
    # "serious" must not fire on comparatives ("more/less serious than last
    # year" are trend anchors, not severity poles) — hence the lookbehinds.
    serious   = list(pos = c("(?<!not )very serious",
                             "(?<!less\\s)(?<!more\\s)(?<!not\\s)\\bserious\\b",
                             "심각(?!\\s?하지)"),
                     neg = c("not.*serious", "심각하지 않")),
    high_low  = list(pos = c("very high", "\\bhigh\\b", "높다", "높은"),
                     neg = c("very low", "\\blow\\b", "낮다", "낮은")),
    fair      = list(pos = c("\\bfair\\b", "공정(?!\\s?하지)"),
                     neg = c("\\bunfair\\b", "불공정", "공정하지 않")),
    likely    = list(pos = c("very likely", "\\blikely\\b"),
                     neg = c("\\bunlikely\\b", "not.*likely"))
  )
}

# Labels that denote missing / non-substantive responses; excluded from polarity.
.MISSING_LABEL_PATTERNS <- c(
  "missing", "don'?t know", "do not know", "can'?t choose", "cannot choose",
  "decline", "refus", "no answer", "not applicable", "\\bn/?a\\b",
  "don'?t understand", "do not understand", "not asked", "no response",
  "haven'?t thought", "not sure",
  # Korean missing/non-substantive conventions.
  "모르겠", "모름", "잘 모르", "무응답", "응답\\s?거절", "거절",
  "해당\\s?없음", "비해당", "선택할 수 없", "생각해\\s?본\\s?적\\s?없"
)

# Locale of a set of label texts: "ko" if any Hangul present, else "en".
.detect_locale <- function(texts) {
  if (length(texts) > 0 && any(grepl("[가-힣]", texts))) "ko" else "en"
}

.norm_label <- function(s) {
  s <- tolower(as.character(s))
  s <- gsub("[[:punct:]]", " ", s)
  s <- gsub("\\s+", " ", s)
  trimws(s)
}

.match_any <- function(s, patterns) {
  any(vapply(patterns, function(p) grepl(p, s, perl = TRUE), logical(1)))
}

# Tier-2 generic Korean predicative morphology, consulted ONLY when no
# specific family matched at all. Korean scale labels are usually predicates
# ("노력한다" / "노력하지 않는다", "위협을 느낀다" / "느끼지 않는다"): the
# negation morpheme ~지 않 marks the negative pole; the positive pole needs
# an INTENSIFIER + predicative ending (매우/아주/다소/약간/많이 … 다/함/됨) —
# a bare 다$ would claim every Korean sentence-form label including midpoints
# (보통이다, 그저 그렇다). Pole detection only needs the extremes, and extreme
# labels carry intensifiers. Resolution is NEGATION-DECISIVE: a negated label
# is neg even though it also ends in 다. Semantically-negative stems
# (불신한다, 불만족한다) are caught by their specific family FIRST, so tier 2
# never sees them — that ordering is what keeps this generic rule safe.
# (~지 못 is deliberately absent: "잊지 못한다"-style forms are affirmative.)
.KO_GENERIC_POLES <- list(
  pos = c("(매우|아주|다소|약간|많이).*(다|함|됨)\\s*$", "잘\\s?(하|되|한|된)"),
  neg = c("지\\s?않")
)

# Classify a single label string -> "pos" | "neg" | "missing" | "unknown".
classify_pole <- function(label_text, lexicon = default_polarity_lexicon()) {
  s <- .norm_label(label_text)
  if (!nzchar(s)) return("unknown")
  if (.match_any(s, .MISSING_LABEL_PATTERNS)) return("missing")
  hit_pos <- FALSE; hit_neg <- FALSE
  for (fam in lexicon) {
    if (.match_any(s, fam$neg)) hit_neg <- TRUE
    if (.match_any(s, fam$pos)) hit_pos <- TRUE
  }
  if (hit_pos && !hit_neg) return("pos")
  if (hit_neg && !hit_pos) return("neg")
  if (hit_pos && hit_neg) return("unknown")  # contradiction — stop here
  # Tier 2: no specific family matched; try generic Korean morphology.
  # Negation is decisive: "필요 하지 않다" ends in 다 too, but 지 않 wins.
  if (.match_any(s, .KO_GENERIC_POLES$neg)) return("neg")
  if (.match_any(s, .KO_GENERIC_POLES$pos)) return("pos")
  "unknown"
}

# Given a named-numeric vector (names = label text, values = numeric codes),
# determine which END of the scale holds the positive pole.
# Returns list(end = "low"|"high"|NA, pos_codes, neg_codes, reason).
find_pole_end <- function(labels_named, lexicon = default_polarity_lexicon()) {
  if (is.null(labels_named) || length(labels_named) < 2) {
    return(list(end = NA_character_, pos_codes = numeric(0),
                neg_codes = numeric(0), reason = "too_few_labels"))
  }
  texts <- names(labels_named)
  codes <- suppressWarnings(as.numeric(labels_named))
  pos_codes <- numeric(0); neg_codes <- numeric(0)
  for (i in seq_along(codes)) {
    if (is.na(codes[i])) next
    p <- classify_pole(texts[i], lexicon)
    if (p == "pos") pos_codes <- c(pos_codes, codes[i])
    if (p == "neg") neg_codes <- c(neg_codes, codes[i])
  }
  if (length(pos_codes) == 0 || length(neg_codes) == 0) {
    return(list(end = NA_character_, pos_codes = pos_codes,
                neg_codes = neg_codes, reason = "no_classifiable_poles"))
  }
  if (max(pos_codes) < min(neg_codes)) {
    return(list(end = "low", pos_codes = pos_codes,
                neg_codes = neg_codes, reason = "ok"))
  }
  if (min(pos_codes) > max(neg_codes)) {
    return(list(end = "high", pos_codes = pos_codes,
                neg_codes = neg_codes, reason = "ok"))
  }
  list(end = NA_character_, pos_codes = pos_codes,
       neg_codes = neg_codes, reason = "poles_overlap")
}

.flip_end <- function(e) if (identical(e, "low")) "high" else if (identical(e, "high")) "low" else NA_character_

# Convert a spec scale.labels list (code-string -> text) to the same
# named-numeric form as haven value labels (names = text, values = codes).
.spec_labels_to_named <- function(spec_labels) {
  if (is.null(spec_labels) || length(spec_labels) == 0) return(NULL)
  codes <- suppressWarnings(as.numeric(names(spec_labels)))
  texts <- as.character(unlist(spec_labels, use.names = FALSE))
  keep <- !is.na(codes) & nzchar(texts)
  if (!any(keep)) return(NULL)
  setNames(codes[keep], texts[keep])
}


# ===========================================================================
# Registry index: full per-fn rows (reverses / scales / flags). Parallel to
# load_reverser_set() in 04_strict_reversal.R but returns the whole row.
# ===========================================================================
.lr_registry_cache <- new.env(parent = emptyenv())

load_registry_index <- function(
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml")
) {
  if (!is.null(.lr_registry_cache$idx)) return(.lr_registry_cache$idx)
  if (!file.exists(registry_path)) {
    stop(sprintf("recoding registry not found at %s", registry_path), call. = FALSE)
  }
  reg <- yaml::read_yaml(registry_path)
  idx <- list()
  for (e in reg) {
    if (is.null(e$fn)) next
    idx[[e$fn]] <- list(
      fn = e$fn,
      reverses = isTRUE(e$reverses),
      monotonic = isTRUE(e$monotonic),
      requires_data = isTRUE(e$requires_data),
      input_scale = e$input_scale,
      output_scale = e$output_scale
    )
  }
  .lr_registry_cache$idx <- idx
  idx
}


# ===========================================================================
# Per-survey raw VALUE-LABEL loaders (Phase 4: all surveys).
#
# Each returns a data frame whose columns retain haven label attributes for
# the given spec wave key, or NULL when unresolvable. Except for ABS (cached
# labeled RDS), these are METADATA-ONLY reads: haven::read_sav(n_max = 0)
# parses just the SPSS header — fast even on WVS w7 — and value labels are
# column metadata, so zero rows suffice.
#
# Pooled-file surveys (kgss, kinu, gcb; kipa-corruption 2004-07) read one
# file regardless of wave key. Per-wave surveys resolve a path per key.
#
# Korean-label files vary in encoding declaration quality: KIPA deposits
# through ~2017 are EUC-KR without a proper declaration (default read gives
# latin-1 mojibake), while 2018+ self-declare (forcing CP949 there ERRORS).
# `ko_retry = TRUE` handles this adaptively: read default; if labels contain
# no Hangul but high-byte latin noise, re-read with encoding = "CP949".
#
# kipa-corruption uses Korean files ONLY (eng_* variants carry known
# mistranslations — 사법부/judiciary labeled "legislature").
# ===========================================================================
.sav_meta_cache <- new.env(parent = emptyenv())
.label_cache <- new.env(parent = emptyenv())

# Do the value labels of df look like EUC-KR read as latin-1?
.labels_look_garbled_ko <- function(df) {
  labs <- unlist(lapply(df, function(x) names(attr(x, "labels"))))
  if (length(labs) == 0) return(FALSE)
  !any(grepl("[가-힣]", labs)) && any(grepl("[À-ÿ]", labs))
}

.read_sav_labels <- function(path, encoding = NULL, ko_retry = FALSE) {
  if (is.null(path) || length(path) == 0 || is.na(path[1]) ||
      !file.exists(path[1])) return(NULL)
  path <- path[1]
  key <- paste0(path, "::", encoding %||% "<default>")
  if (!is.null(.sav_meta_cache[[key]])) return(.sav_meta_cache[[key]])
  df <- tryCatch(haven::read_sav(path, n_max = 0, encoding = encoding),
                 error = function(e) NULL)
  if (!is.null(df) && ko_retry && is.null(encoding) &&
      .labels_look_garbled_ko(df)) {
    df2 <- tryCatch(haven::read_sav(path, n_max = 0, encoding = "CP949"),
                    error = function(e) NULL)
    if (!is.null(df2) && !.labels_look_garbled_ko(df2)) df <- df2
  }
  if (!is.null(df)) .sav_meta_cache[[key]] <- df
  df
}

# Pick one .sav from a directory (optionally filtered / largest-by-size).
.pick_sav <- function(dir, pattern = NULL, exclude = NULL, largest = FALSE) {
  if (is.null(dir) || !dir.exists(dir)) return(NULL)
  fs <- list.files(dir, pattern = "\\.sav$", full.names = TRUE,
                   ignore.case = TRUE)
  if (!is.null(exclude)) fs <- fs[!grepl(exclude, basename(fs), ignore.case = TRUE)]
  if (!is.null(pattern)) fs <- fs[grepl(pattern, basename(fs), ignore.case = TRUE)]
  if (length(fs) == 0) return(NULL)
  if (largest) fs[which.max(file.size(fs))] else fs[1]
}

# KIPA deposit-handle -> survey year (mirrors 0_load_waves.R's map).
.KIPA_YEAR_HANDLE <- c(
  `2008` = "13988", `2009` = "15387", `2010` = "15386", `2011` = "15356",
  `2012` = "15788", `2013` = "23278", `2014` = "23277", `2015` = "23276",
  `2016` = "23275", `2017` = "23266", `2018` = "24741", `2019` = "24742",
  `2020` = "24743", `2021` = "25785", `2022` = "26248", `2023` = "30856"
)

# IPUS years whose .sav needs an explicit CP949 (mirrors 0_load_waves.R).
.IPUS_CP949_YEARS <- c(2008, 2009, 2013, 2014, 2015, 2016)

.SURVEY_LABEL_LOADER <- list(
  abs = function(wave_key) {
    if (!grepl("^w[0-9]+$", wave_key)) return(NULL)
    n <- sub("^w", "", wave_key)
    p <- here::here("data", "processed", paste0("w", n, ".rds"))
    if (!file.exists(p)) return(NULL)
    ck <- paste0("abs::", wave_key)
    if (is.null(.label_cache[[ck]])) .label_cache[[ck]] <- readRDS(p)
    .label_cache[[ck]]
  },
  wvs = function(wave_key) {
    files <- c(
      w1 = "wave1/WV1_Data_spss_v20200208.sav",
      w2 = "wave2/WV2_Data_Spss_v20180912.sav",
      w3 = "wave3/WV3_Data_Spss_v20180912.sav",
      w4 = "wave4/WV4_Data_spss_v20201117.sav",
      w5 = "wave5/WV5_Data_Spss_v20180912.sav",
      w6 = "wave6/WV6_Data_sav_v20201117.sav",
      w7 = "wave7/WVS_Cross-National_Wave_7_spss_v6_0.sav"
    )
    if (!wave_key %in% names(files)) return(NULL)
    enc <- if (wave_key %in% c("w6", "w7")) NULL else "latin1"
    .read_sav_labels(here::here("data", "wvs", "raw", files[[wave_key]]),
                     encoding = enc)
  },
  lbs = function(wave_key) {
    yr <- sub("^y", "", wave_key)
    if (!grepl("^[0-9]{4}$", yr)) return(NULL)
    .read_sav_labels(
      .pick_sav(here::here("data", "lbs", "raw", yr), pattern = "eng"),
      encoding = "latin1")
  },
  afro = function(wave_key) {
    n <- sub("^w", "", wave_key)
    if (!grepl("^[0-9]+$", n)) return(NULL)
    d <- here::here("data", "afro", "raw", paste0("round", n))
    p <- file.path(d, sprintf("merged_r%s_data.sav", n))
    if (!file.exists(p)) p <- .pick_sav(d, largest = TRUE)  # r9 nonstandard name
    .read_sav_labels(p, encoding = "latin1")
  },
  `arab-barometer` = function(wave_key) {
    n <- sub("^w", "", wave_key)
    if (!grepl("^[0-9]+$", n)) return(NULL)
    .read_sav_labels(
      .pick_sav(here::here("data", "arab-barometer", "raw", paste0("wave", n)),
                largest = TRUE),
      encoding = "latin1")
  },
  kamos = function(wave_key) {
    n <- sub("^w", "", wave_key)
    if (!grepl("^[0-9]+$", n)) return(NULL)
    .read_sav_labels(
      .pick_sav(here::here("data", "kamos", "raw", "all_waves"),
                pattern = sprintf("^KAMOS_%s-1_.*data", n)),
      ko_retry = TRUE)
  },
  kgss = function(wave_key) {
    .read_sav_labels(here::here("data", "kgss", "raw", "kor_data_CUM0074.sav"),
                     ko_retry = TRUE)
  },
  `kipa-corruption` = function(wave_key) {
    yr <- sub("^w", "", wave_key)
    if (!grepl("^[0-9]{4}$", yr)) return(NULL)
    base <- here::here("data", "kipa-corruption", "raw", "unzipped")
    if (yr %in% as.character(2004:2007)) {
      return(.read_sav_labels(file.path(base, "13081", "kor_data_cum0009.sav"),
                              ko_retry = TRUE))
    }
    h <- unname(.KIPA_YEAR_HANDLE[yr])
    if (is.na(h)) return(NULL)
    .read_sav_labels(
      .pick_sav(file.path(base, h), pattern = "^kor_data", exclude = "^eng_"),
      ko_retry = TRUE)
  },
  kinu = function(wave_key) {
    # Pooled file; a/b subwave keys (w2019a...) all resolve here.
    .read_sav_labels(here::here("data", "kinu", "raw", "kinu_2014-2023_en.sav"))
  },
  ipus = function(wave_key) {
    yr <- sub("^w", "", wave_key)
    if (!grepl("^[0-9]{4}$", yr)) return(NULL)
    enc <- if (as.integer(yr) %in% .IPUS_CP949_YEARS) "CP949" else NULL
    .read_sav_labels(
      here::here("data", "ipus", "raw", yr, paste0("ipus_", yr, ".sav")),
      encoding = enc, ko_retry = TRUE)
  },
  gcb = function(wave_key) {
    .read_sav_labels(here::here("data", "gcb", "raw", "asia2020",
                                "GCB_Edition10_Asia_2020.sav"))
  }
)

# Extract the value-label vector for one source variable from a loaded wave df.
.get_value_labels <- function(wave_df, src) {
  if (is.null(wave_df) || is.null(src) || !src %in% names(wave_df)) return(NULL)
  lab <- attr(wave_df[[src]], "labels")
  if (is.null(lab) || length(lab) == 0) return(NULL)
  # haven stores names = label text, values = codes — exactly our convention.
  lab
}


# ===========================================================================
# Map raw pole codes through a method:recode literal mapping, mirroring
# harmonize.R semantics: unmapped codes and YAML nulls become NA (dropped).
# ===========================================================================
.map_pole_codes <- function(codes, recode_map) {
  out <- numeric(0)
  for (cc in codes) {
    v <- recode_map[[as.character(cc)]]
    if (is.null(v)) next
    v <- suppressWarnings(as.numeric(v))
    if (!is.na(v)) out <- c(out, v)
  }
  out
}


# ===========================================================================
# Reconcile ONE (variable, wave). raw_labels / spec_labels are parameters so
# this is unit-testable with synthetic inputs (no .sav read).
#
# Phase 4 extensions:
#   recode_map      — method:recode literal mapping; when given, the realized
#                     end comes from pushing raw pole codes through the map
#                     (fn_entry is not consulted).
#   verbatim_labels — named-numeric (names = label text, values = codes)
#                     declared-side fallback from the verbatim dictionary's
#                     response_scale, used only when scale.labels are absent.
#   missing_codes   — codes the engine masks to NA for this variable (per its
#                     missing convention). Their labels are removed from the
#                     RAW side before pole detection, exactly as the engine
#                     removes the values — an "8=없다 / 9=무응답" response
#                     code must not register as a substantive pole.
# ===========================================================================
reconcile_one <- function(survey, var_id, wave_key, source_var, fn_name,
                          fn_entry, raw_labels, spec_labels,
                          var_type = NULL,
                          lexicon = default_polarity_lexicon(),
                          recode_map = NULL,
                          verbatim_labels = NULL,
                          missing_codes = numeric(0)) {
  if (length(missing_codes) > 0 && !is.null(raw_labels)) {
    raw_labels <- raw_labels[!(as.numeric(raw_labels) %in% as.numeric(missing_codes))]
  }
  locale <- .detect_locale(names(raw_labels))
  mk <- function(status, reason, message,
                 raw_end = NA_character_, realized_end = NA_character_,
                 declared_end = NA_character_, reverses = NA,
                 declared_source = "scale_labels") {
    tibble(
      survey = survey, variable = var_id, wave = wave_key,
      source_var = source_var %||% NA_character_, fn = fn_name %||% NA_character_,
      reverses = reverses, raw_pos_end = raw_end,
      realized_pos_end = realized_end, declared_pos_end = declared_end,
      declared_source = declared_source,
      label_locale = locale, status = status, reason = reason, message = message
    )
  }

  if (identical(var_type, "nominal")) {
    return(mk("skip", "nominal_no_polarity", "nominal variable — no pole"))
  }
  is_recode <- !is.null(recode_map)
  # Resolve fn direction (not needed for method:recode — the map decides).
  if (!is_recode) {
    if (is.null(fn_entry)) {
      return(mk("skip", "unknown_fn",
                sprintf("fn '%s' not in recoding registry", fn_name %||% "NULL")))
    }
    if (isTRUE(fn_entry$requires_data)) {
      return(mk("skip", "conditional_fn",
                sprintf("fn '%s' is data-conditional; delegated to anchor check", fn_name),
                reverses = fn_entry$reverses))
    }
    if (!isTRUE(fn_entry$monotonic)) {
      return(mk("skip", "non_monotonic_fn",
                sprintf("fn '%s' not monotone; cannot map ends", fn_name),
                reverses = fn_entry$reverses))
    }
  }
  fn_reverses <- if (is_recode) NA else fn_entry$reverses

  # RAW side (ground truth).
  raw <- find_pole_end(raw_labels, lexicon)
  if (is.na(raw$end)) {
    return(mk("skip", paste0("unanchorable_raw:", raw$reason),
              sprintf("raw labels not pole-anchorable (%s)", raw$reason),
              reverses = fn_reverses))
  }
  # DECLARED side: spec scale.labels first, verbatim response_scale fallback.
  declared_source <- "scale_labels"
  spec_named <- .spec_labels_to_named(spec_labels)
  if (is.null(spec_named) && !is.null(verbatim_labels) &&
      length(verbatim_labels) >= 2) {
    spec_named <- verbatim_labels
    declared_source <- "verbatim_response_scale"
  }
  if (is.null(spec_named)) {
    return(mk("skip", "no_declared_labels",
              "no scale.labels and no verbatim response_scale",
              raw_end = raw$end, reverses = fn_reverses))
  }
  decl <- find_pole_end(spec_named, lexicon)
  if (is.na(decl$end)) {
    return(mk("skip", paste0("no_declared_direction:", decl$reason),
              sprintf("declared labels (%s) not pole-anchorable (%s)",
                      declared_source, decl$reason),
              raw_end = raw$end, reverses = fn_reverses,
              declared_source = declared_source))
  }

  # REALIZED side: where the raw positive pole lands in the output.
  if (is_recode) {
    mapped_pos <- .map_pole_codes(raw$pos_codes, recode_map)
    mapped_neg <- .map_pole_codes(raw$neg_codes, recode_map)
    if (length(mapped_pos) == 0 || length(mapped_neg) == 0) {
      return(mk("skip", "recode_poles_unmapped",
                "mapping sends >=1 pole entirely to NA; cannot place output pole",
                raw_end = raw$end, reverses = fn_reverses,
                declared_source = declared_source))
    }
    realized_end <- if (max(mapped_pos) < min(mapped_neg)) "low" else
                    if (min(mapped_pos) > max(mapped_neg)) "high" else NA_character_
    if (is.na(realized_end)) {
      return(mk("skip", "recode_poles_overlap_output",
                "mapped pole codes interleave in output; cannot place output pole",
                raw_end = raw$end, reverses = fn_reverses,
                declared_source = declared_source))
    }
    fn_verb <- "mapping sends it to"
  } else {
    realized_end <- if (isTRUE(fn_entry$reverses)) .flip_end(raw$end) else raw$end
    fn_verb <- if (isTRUE(fn_entry$reverses)) "reverses" else "keeps"
  }

  if (identical(realized_end, decl$end)) {
    mk("ok", "ok_match",
       sprintf("direction consistent (raw pos=%s, fn %s, declared pos=%s)",
               raw$end, fn_verb, decl$end),
       raw_end = raw$end, realized_end = realized_end,
       declared_end = decl$end, reverses = fn_reverses,
       declared_source = declared_source)
  } else {
    mk("error", "opposite_labels",
       sprintf(paste0("STORED OPPOSITE ITS LABELS: raw positive pole at %s end, ",
                      "fn %s -> output positive pole at %s end, but declared ",
                      "labels (%s) put positive pole at %s end"),
               raw$end, fn_verb, realized_end, declared_source, decl$end),
       raw_end = raw$end, realized_end = realized_end,
       declared_end = decl$end, reverses = fn_reverses,
       declared_source = declared_source)
  }
}


# ===========================================================================
# Verbatim response_scale fallback index (declared side, Phase 4).
# Parses "1=Very difficult, 2=Difficult, 3=Easy, 4=Very easy" into the same
# named-numeric shape as haven value labels (names = text, values = codes).
#
# CONVENTION GATE (empirical, 2026-07-03): what response_scale documents
# VARIES BY SURVEY.
#   - abs: the INTENDED post-harmonization direction (verified: system_capable
#     w3 shows 4=Strongly agree = harmonized order, opposite the raw .sav;
#     democracy_satisfaction w3 likewise). Valid as the DECLARED side.
#   - kgss: the RAW questionnaire scale (decisive: rows carry raw missing
#     codes like "-8=Don't know", which no harmonized variable has).
#   - lbs: the RAW scale (dem_solves_problems y2020/y2023 document
#     1=Strongly agree = raw order on a correctly reversed item; treating it
#     as declared produced 2 false errors in the first Phase 4 sweep).
# A raw-convention response_scale used as the declared side flags every
# correctly-REVERSED item as an error, so the fallback is enabled ONLY for
# surveys whose dictionary is verified to use the intended-direction
# convention. Extend this vector only after checking a known-reversed item
# in that survey's dictionary.
# ===========================================================================
.VERBATIM_DECLARED_SURVEYS <- c("abs")
.parse_response_scale <- function(s) {
  if (is.null(s) || is.na(s) || !nzchar(trimws(s))) return(NULL)
  toks <- unlist(strsplit(as.character(s), "[,;]"))
  codes <- numeric(0); texts <- character(0)
  for (t in toks) {
    m <- regmatches(t, regexec("^\\s*(-?[0-9]+(?:\\.[0-9]+)?)\\s*=\\s*(.+?)\\s*$", t))[[1]]
    if (length(m) == 3) {
      codes <- c(codes, suppressWarnings(as.numeric(m[2])))
      texts <- c(texts, m[3])
    }
  }
  keep <- !is.na(codes)
  if (sum(keep) < 2) return(NULL)
  setNames(codes[keep], texts[keep])
}

# Digit-canonical wave key, so spec keys ("w2003") and verbatim keys ("y2003")
# meet regardless of prefix convention.
.wave_digits <- function(x) gsub("[^0-9]", "", tolower(as.character(x)))

.verbatim_declared_cache <- new.env(parent = emptyenv())

load_verbatim_declared <- function(survey) {
  if (!is.null(.verbatim_declared_cache[[survey]])) {
    return(.verbatim_declared_cache[[survey]])
  }
  path <- here::here("data", survey, "questionnaire_text",
                     paste0(gsub("-", "_", survey), "_verbatim_items.csv"))
  idx <- list()
  if (file.exists(path)) {
    v <- tryCatch(utils::read.csv(path, stringsAsFactors = FALSE),
                  error = function(e) NULL)
    need <- c("harmonized_name", "wave", "response_scale")
    if (!is.null(v) && all(need %in% names(v))) {
      for (i in seq_len(nrow(v))) {
        rs <- v$response_scale[i]
        if (is.na(rs) || !nzchar(trimws(rs))) next
        key <- paste0(v$harmonized_name[i], "::", .wave_digits(v$wave[i]))
        if (is.null(idx[[key]])) idx[[key]] <- .parse_response_scale(rs)
      }
    }
  }
  .verbatim_declared_cache[[survey]] <- idx
  idx
}


# ===========================================================================
# Survey driver.
# ===========================================================================
compute_label_reconciliation <- function(survey, spec_files = NULL,
                                         registry_index = NULL,
                                         lexicon = default_polarity_lexicon()) {
  if (is.null(registry_index)) registry_index <- load_registry_index()
  # Declared-side fallback only where the dictionary convention is verified
  # intended-direction (see .VERBATIM_DECLARED_SURVEYS note above).
  verbatim_idx <- if (survey %in% .VERBATIM_DECLARED_SURVEYS) {
    load_verbatim_declared(survey)
  } else {
    list()
  }

  label_loader <- .SURVEY_LABEL_LOADER[[survey]]
  if (is.null(label_loader)) {
    return(tibble(
      survey = survey, variable = NA_character_, wave = NA_character_,
      source_var = NA_character_, fn = NA_character_, reverses = NA,
      raw_pos_end = NA_character_, realized_pos_end = NA_character_,
      declared_pos_end = NA_character_, declared_source = NA_character_,
      label_locale = NA_character_, status = "skip",
      reason = "no_label_loader",
      message = sprintf("no value-label loader for survey '%s' (add to .SURVEY_LABEL_LOADER)", survey)
    ))
  }

  if (is.null(spec_files)) {
    if (!exists("list_survey_specs", mode = "function")) {
      source(here::here("src", "r", "utils", "spec_discovery.R"))
    }
    spec_files <- list_survey_specs(survey)
  }

  rows <- list()
  for (spec_path in spec_files) {
    spec <- yaml::read_yaml(spec_path)
    missing_conventions <- spec$missing_conventions %||% list()
    for (v in spec$variables %||% list()) {
      var_missing_codes <- .resolve_missing_codes(v, missing_conventions)
      wave_keys <- names(v$source %||% list())
      for (wave_key in wave_keys) {
        src <- v$source[[wave_key]]
        if (is.null(src)) next  # explicit null -> skipped wave

        rule <- .resolve_wave_rule(v, wave_key)
        method <- rule$method %||% "identity"

        # Resolve fn_entry / recode_map by method.
        recode_map <- NULL
        if (identical(method, "identity")) {
          fn_name <- "identity"
          fn_entry <- list(fn = "identity", reverses = FALSE, monotonic = TRUE,
                           requires_data = FALSE)
        } else if (identical(method, "r_function")) {
          fn_name <- rule$fn %||% ""
          fn_entry <- registry_index[[fn_name]]  # may be NULL -> unknown_fn
        } else if (identical(method, "recode")) {
          fn_name <- "recode"
          fn_entry <- NULL
          recode_map <- rule$mapping
          if (is.null(recode_map) || length(recode_map) == 0) {
            rows[[length(rows) + 1]] <- reconcile_one(
              survey, v$id, wave_key, src, "recode", NULL, NULL, NULL,
              var_type = v$type)
            rows[[length(rows)]]$reason <- "recode_no_mapping"
            rows[[length(rows)]]$message <- "method=recode without a mapping field"
            next
          }
        } else {
          rows[[length(rows) + 1]] <- reconcile_one(
            survey, v$id, wave_key, src, method, NULL, NULL, NULL,
            var_type = v$type)
          rows[[length(rows)]]$reason <- "derived_not_reconcilable"
          rows[[length(rows)]]$message <- sprintf("method=%s not reconcilable", method)
          next
        }

        wave_df <- label_loader(wave_key)
        raw_labels <- .get_value_labels(wave_df, src)

        rows[[length(rows) + 1]] <- reconcile_one(
          survey = survey, var_id = v$id, wave_key = wave_key, source_var = src,
          fn_name = fn_name, fn_entry = fn_entry,
          raw_labels = raw_labels, spec_labels = v$scale$labels,
          var_type = v$type, lexicon = lexicon,
          recode_map = recode_map,
          verbatim_labels = verbatim_idx[[paste0(v$id, "::", .wave_digits(wave_key))]],
          missing_codes = var_missing_codes
        )
      }
    }
  }

  if (length(rows) == 0) {
    return(tibble(
      survey = character(0), variable = character(0), wave = character(0),
      source_var = character(0), fn = character(0), reverses = logical(0),
      raw_pos_end = character(0), realized_pos_end = character(0),
      declared_pos_end = character(0), declared_source = character(0),
      label_locale = character(0), status = character(0),
      reason = character(0), message = character(0)
    ))
  }
  bind_rows(rows)
}


# ===========================================================================
# Run + write CSV + summary.
# ===========================================================================
run_label_reconciliation <- function(survey, output_dir = NULL) {
  if (is.null(output_dir)) output_dir <- here::here("audit", "reports", survey)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  results <- compute_label_reconciliation(survey)
  csv_path <- file.path(output_dir, "04-label-reconciliation.csv")
  write.csv(results, csv_path, row.names = FALSE)

  status_levels <- c("ok", "error", "skip")
  counts <- if (nrow(results) > 0) {
    as.list(table(factor(results$status, levels = status_levels)))
  } else setNames(as.list(rep(0L, 3)), status_levels)

  cat(sprintf("\n[label reconciliation] survey=%s\n", survey))
  cat(sprintf("  total checks: %d (ok=%d, error=%d, skip=%d)\n",
              nrow(results), counts$ok %||% 0, counts$error %||% 0, counts$skip %||% 0))
  cat(sprintf("  CSV: %s\n", csv_path))

  if ((counts$skip %||% 0) > 0) {
    sk <- results[results$status == "skip", , drop = FALSE]
    by_reason <- sort(table(sub(":.*$", "", sk$reason)), decreasing = TRUE)
    cat("  skip reasons: ",
        paste(sprintf("%s=%d", names(by_reason), as.integer(by_reason)), collapse = ", "),
        "\n", sep = "")
  }

  errs <- results[results$status == "error", , drop = FALSE]
  if (nrow(errs) > 0) {
    cat(sprintf("\n  *** %d ERROR row(s) — stored opposite documented labels:\n", nrow(errs)))
    print(as.data.frame(errs[, c("variable", "wave", "fn", "raw_pos_end",
                                 "realized_pos_end", "declared_pos_end")]),
          row.names = FALSE)
    cat("\n  -> Each error: the harmonized variable points opposite its own\n")
    cat("     scale.labels. Fix the fn (reverse <-> non-reverse) or the labels.\n\n")
  }
  invisible(results)
}

run_all_surveys <- function() {
  supported <- names(.SURVEY_LABEL_LOADER)
  all_results <- list()
  for (survey in supported) {
    res <- tryCatch(run_label_reconciliation(survey), error = function(e) {
      cat(sprintf("\n[label reconciliation] %s: %s\n", survey, conditionMessage(e)))
      NULL
    })
    if (!is.null(res)) all_results[[survey]] <- res
  }
  bind_rows(all_results)
}


# ===========================================================================
# CLI.
# ===========================================================================
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey      <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys") { out$all_surveys <- TRUE;        i <- i + 1; next }
    if (a == "--output-dir")  { out$output_dir  <- argv[i + 1]; i <- i + 2; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_label_reconciliation.R\n",
          "         (--survey <name> | --all-surveys) [--output-dir <path>]\n",
          "\nReconcile raw .sav value-label polarity (transformed by the\n",
          "declared fn) against the spec's scale.labels. error = stored\n",
          "opposite its labels. Exit 0 if no errors, 1 otherwise.\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey) && !out$all_surveys) {
    stop("usage: --survey <name> OR --all-surveys (see --help)", call. = FALSE)
  }
  out
}

if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    results <- if (args$all_surveys) run_all_surveys() else
      run_label_reconciliation(args$survey, output_dir = args$output_dir)
    n_err <- sum(results$status == "error", na.rm = TRUE)
    if (n_err > 0) quit(status = 1) else quit(status = 0)
  }
}
