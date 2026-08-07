#!/usr/bin/env Rscript
# src/r/audit/04_battery_coherence.R
#
# Layer 4 — Battery-coherence hints (Check B; Phase 3 of the harmonization
# auditor, 2026-07-03).
#
# A reversed item inside an agree/disagree battery leaves a distinctive
# statistical signature in the HARMONIZED output: it correlates negatively
# with its battery-mates and its mean sits away from theirs (the exact
# pre-fix system_deserves_support signature: r<0 vs its three mates, mean
# ~2.1 vs ~2.8). This check looks for that signature directly, so it needs
# no raw .sav loader, no registry, and no anchor file — only the harmonized
# output plus the survey's verbatim question dictionary. It therefore runs
# on every survey immediately.
#
# Battery definition:
#   1. Primary: rows of data/{survey}/questionnaire_text/*_verbatim_items.csv
#      sharing a non-empty `stem_text` within a wave (>= min_size items).
#      Items without a stem are excluded — which is what keeps the known
#      intentional opposite (system_needs_change, a stand-alone item) out of
#      the system-support battery by construction.
#   2. Fallback: variables not in any stem battery are grouped by spec
#      `concept` + observed scale signature (min..max of harmonized values).
#
# Signals per item x battery x wave (pooled across countries):
#   neg_corr     — median Pearson r vs siblings <= -corr_floor
#   mean_outlier — robust z of the item mean vs the battery's modal-scale
#                  reference group (median/MAD) beyond z_cutoff; if MAD ~ 0,
#                  absolute deviation > dev_fallback. Items whose observed
#                  range differs from the modal scale are still evaluated
#                  (a missing +1 shift must not exempt itself).
#
# Severity: SOFT / HINT ONLY. False positives are expected (concept != battery;
# genuinely bipolar batteries; cross-survey coding differences). A hint that
# coincides with a label-reconciliation ERROR (04_label_reconciliation.R) or an
# anchor sign_disagreement (04_anchor_diagnostic.R) is a high-confidence bug.
#
# Public API:
#   load_verbatim_items(survey, path = NULL)             -> tibble or NULL
#   build_stem_batteries(verbatim, min_size = 3)         -> battery tibble
#   build_concept_batteries(survey, harmonized, ...)     -> battery tibble
#   compute_battery_coherence(survey, ...)               -> results tibble
#   run_battery_coherence(survey, ...)                   -> write CSV + summary
#
# CLI:
#   Rscript src/r/audit/04_battery_coherence.R --survey abs
#   Rscript src/r/audit/04_battery_coherence.R --all-surveys
#
# Status meanings:
#   ok    — item coheres with its battery (median sibling r >= corr_floor)
#   hint  — neg_corr and/or mean_outlier fired (possible direction bug)
#   weak  — |median sibling r| below corr_floor and no outlier (uninformative)
#   na    — no sibling pair reached min_pair_n complete cases
#   skip  — item/battery not evaluable in this wave (reason in message)
#
# Exit code: 0 always (soft check; never blocks).

suppressPackageStartupMessages({
  library(yaml)
  library(here)
  library(dplyr)
  library(tibble)
})

# Reused helpers: normalize_wave_key(), load_harmonized_for_survey(),
# .compute_corr_row(). Sourcing is CLI-safe (sys.nframe() guard there).
source(here::here("src", "r", "audit", "04_anchor_diagnostic.R"))

`%||%` <- function(a, b) if (!is.null(a)) a else b

.BATTERY_DEFAULTS <- list(
  corr_floor   = 0.10,  # |median sibling r| below this = weak; <= -this = neg_corr
  z_cutoff     = 3.5,   # robust-z cutoff for the mean-outlier signal
  min_pair_n   = 30,    # pairwise complete cases required for an r to count
  min_size     = 3,     # min items with data for a battery-wave to be evaluated
  dev_fallback = 0.5,   # |mean - median| cutoff when MAD ~ 0 (scale points)
  mad_eps      = 1e-8
)

# Types eligible for the concept-fallback grouping.
.BATTERY_TYPES <- c("ordinal", "continuous")


# ---------------------------------------------------------------------------
# Wave-key canonicalization for JOINING (display keys stay as-is).
# Verbatim CSVs and harmonized outputs use per-survey conventions ("w3",
# "y1995", "r5", integer 3/2003). Both sides reduce to their digit content,
# which is identical within a survey ("w3" ~ 3 -> "3"; "y1995" ~ "y1995").
# ---------------------------------------------------------------------------
.canon_wave <- function(x) {
  s <- tolower(as.character(normalize_wave_key(x)))
  d <- gsub("[^0-9]", "", s)
  ifelse(nzchar(d), d, s)
}


# ---------------------------------------------------------------------------
# Load the survey's verbatim question dictionary. Returns NULL (with no
# error) when the survey has none — the caller falls back to concept
# grouping only.
# ---------------------------------------------------------------------------
load_verbatim_items <- function(survey, path = NULL) {
  if (is.null(path)) {
    stem <- gsub("-", "_", survey)
    path <- here::here("data", survey, "questionnaire_text",
                       paste0(stem, "_verbatim_items.csv"))
  }
  if (!file.exists(path)) return(NULL)
  v <- utils::read.csv(path, stringsAsFactors = FALSE)
  required <- c("wave", "harmonized_name", "stem_text")
  missing_cols <- setdiff(required, names(v))
  if (length(missing_cols) > 0) {
    warning(sprintf("verbatim CSV %s missing columns: %s — skipping stem batteries",
                    path, paste(missing_cols, collapse = ", ")))
    return(NULL)
  }
  if (!"notes" %in% names(v)) v$notes <- ""
  v
}


# ---------------------------------------------------------------------------
# Batteries from shared stem_text. One battery per (wave x normalized stem)
# with >= min_size distinct harmonized names. Rows marked "Not included in
# this wave" are dropped first, so absence rows don't inflate membership.
# ---------------------------------------------------------------------------
build_stem_batteries <- function(verbatim, min_size = .BATTERY_DEFAULTS$min_size) {
  empty <- tibble(battery_id = character(0), battery_source = character(0),
                  stem_excerpt = character(0), wave = character(0),
                  wave_key = character(0), variable = character(0))
  if (is.null(verbatim) || nrow(verbatim) == 0) return(empty)

  v <- verbatim
  v$stem_norm <- tolower(gsub("\\s+", " ", trimws(as.character(v$stem_text))))
  keep <- !is.na(v$stem_norm) & nzchar(v$stem_norm) &
          !grepl("not included in this wave", v$notes %||% "", ignore.case = TRUE)
  v <- v[keep, , drop = FALSE]
  if (nrow(v) == 0) return(empty)

  v <- unique(v[, c("wave", "stem_norm", "harmonized_name")])
  key <- paste(v$wave, v$stem_norm, sep = "\r")
  sizes <- table(key)
  v <- v[key %in% names(sizes)[sizes >= min_size], , drop = FALSE]
  if (nrow(v) == 0) return(empty)

  key <- paste(v$wave, v$stem_norm, sep = "\r")
  idx <- match(key, unique(key))
  tibble(
    battery_id = sprintf("stem:%s#%02d", v$wave, idx),
    battery_source = "stem",
    stem_excerpt = substr(v$stem_norm, 1, 60),
    wave = as.character(v$wave),
    wave_key = .canon_wave(v$wave),
    variable = v$harmonized_name
  )
}


# ---------------------------------------------------------------------------
# Fallback batteries: spec concept x observed scale signature.
# concept_map may be injected for tests; by default it is parsed from the
# survey's production specs (id, concept, type).
# ---------------------------------------------------------------------------
.read_concept_map <- function(survey) {
  if (!exists("list_survey_specs", mode = "function")) {
    source(here::here("src", "r", "utils", "spec_discovery.R"))
  }
  rows <- list()
  for (spec_path in list_survey_specs(survey)) {
    spec <- tryCatch(yaml::read_yaml(spec_path), error = function(e) NULL)
    for (v in spec$variables %||% list()) {
      if (is.null(v$id)) next
      rows[[length(rows) + 1]] <- tibble(
        variable = v$id,
        concept = v$concept %||% NA_character_,
        type = v$type %||% NA_character_
      )
    }
  }
  if (length(rows) == 0) {
    return(tibble(variable = character(0), concept = character(0),
                  type = character(0)))
  }
  unique(bind_rows(rows))
}

.scale_signature <- function(x) {
  x <- suppressWarnings(as.numeric(x))
  x <- x[!is.na(x)]
  if (length(x) == 0) return(NA_character_)
  sprintf("%g..%g", min(x), max(x))
}

build_concept_batteries <- function(survey, harmonized,
                                    exclude = character(0),
                                    concept_map = NULL,
                                    min_size = .BATTERY_DEFAULTS$min_size) {
  empty <- tibble(battery_id = character(0), battery_source = character(0),
                  stem_excerpt = character(0), wave = character(0),
                  wave_key = character(0), variable = character(0))
  if (is.null(concept_map)) concept_map <- .read_concept_map(survey)
  cm <- concept_map[
    !is.na(concept_map$concept) &
    concept_map$type %in% .BATTERY_TYPES &
    concept_map$variable %in% names(harmonized) &
    !(concept_map$variable %in% exclude), , drop = FALSE]
  if (nrow(cm) == 0) return(empty)

  cm$sig <- vapply(cm$variable, function(v) .scale_signature(harmonized[[v]]),
                   character(1))
  cm <- cm[!is.na(cm$sig), , drop = FALSE]
  key <- paste(cm$concept, cm$sig, sep = "\r")
  sizes <- table(key)
  cm <- cm[key %in% names(sizes)[sizes >= min_size], , drop = FALSE]
  if (nrow(cm) == 0) return(empty)

  # Wave-independent: wave/wave_key NA; expanded to all waves at compute time.
  tibble(
    battery_id = sprintf("concept:%s:%s", cm$concept, cm$sig),
    battery_source = "concept",
    stem_excerpt = cm$concept,
    wave = NA_character_,
    wave_key = NA_character_,
    variable = cm$variable
  )
}


# ---------------------------------------------------------------------------
# Harmonized loader with the underscore-name fallback the shared loader
# lacks (arab-barometer -> arab_barometer_harmonized.rds, etc.).
# ---------------------------------------------------------------------------
.find_harmonized_path <- function(survey) {
  us <- gsub("-", "_", survey)
  candidates <- c(
    here::here("data", "processed", sprintf("%s_harmonized.rds", survey)),
    here::here("data", "processed", sprintf("%s_harmonized.rds", us)),
    here::here("outputs", survey, "harmonized.rds")
  )
  hit <- candidates[file.exists(candidates)][1]
  if (is.na(hit)) {
    stop(sprintf("no harmonized .rds for survey '%s' (tried: %s)",
                 survey, paste(candidates, collapse = ", ")), call. = FALSE)
  }
  hit
}


# ---------------------------------------------------------------------------
# Signal computation for one battery x wave. `sub` is the wave-subset data;
# `members` the variables with data. Returns one row per member.
# ---------------------------------------------------------------------------
.battery_wave_rows <- function(sub, members, meta, opts) {
  m <- length(members)
  # Pairwise Pearson among members (upper triangle, mirrored).
  r_mat <- matrix(NA_real_, m, m, dimnames = list(members, members))
  for (i in seq_len(m - 1)) {
    for (j in (i + 1):m) {
      cr <- .compute_corr_row(sub[[members[i]]], sub[[members[j]]])
      if (!is.na(cr$pearson) && cr$n >= opts$min_pair_n) {
        r_mat[i, j] <- cr$pearson
        r_mat[j, i] <- cr$pearson
      }
    }
  }

  item_means <- vapply(members, function(v) mean(sub[[v]], na.rm = TRUE),
                       numeric(1))
  item_ns <- vapply(members, function(v) sum(!is.na(sub[[v]])), integer(1))

  # Mean-outlier reference: the battery's MODAL observed-scale group. Every
  # item — including one whose observed range differs (e.g. a missing +1
  # shift leaves 2..4 against mates' 1..4) — is evaluated against this
  # reference; subgrouping by an item's own signature would let exactly the
  # miscoded item escape its own check.
  sigs <- vapply(members, function(v) .scale_signature(sub[[v]]), character(1))
  sig_tab <- table(sigs)
  modal_sig <- names(sig_tab)[which.max(sig_tab)]
  ref <- which(sigs == modal_sig)
  have_ref <- length(ref) >= opts$min_size
  ref_med <- if (have_ref) stats::median(item_means[ref]) else NA_real_
  ref_mad <- if (have_ref) stats::mad(item_means[ref]) else NA_real_

  rows <- vector("list", m)
  for (i in seq_len(m)) {
    rs <- r_mat[i, -i]
    rs <- rs[!is.na(rs)]
    k <- length(rs)
    med_r <- if (k > 0) stats::median(rs) else NA_real_

    z <- NA_real_
    batt_med <- ref_med
    outlier <- FALSE
    if (have_ref) {
      dev <- item_means[i] - ref_med
      if (ref_mad > opts$mad_eps) {
        z <- dev / ref_mad
        outlier <- abs(z) > opts$z_cutoff
      } else {
        outlier <- abs(dev) > opts$dev_fallback
      }
    }

    neg <- !is.na(med_r) && med_r <= -opts$corr_floor

    if (k == 0 && !outlier) {
      status <- "na"
      message <- sprintf("no sibling pair with n >= %d", opts$min_pair_n)
    } else if (neg || outlier) {
      status <- "hint"
      parts <- character(0)
      if (neg) parts <- c(parts, sprintf(
        "correlates negatively with battery (median r=%.3f vs %d sibling%s)",
        med_r, k, if (k == 1) "" else "s"))
      if (outlier) parts <- c(parts, sprintf(
        "mean outlier (z=%s; item %.2f vs battery median %.2f)",
        if (is.na(z)) "MAD~0" else sprintf("%.1f", z),
        item_means[i], batt_med))
      if (sigs[i] != modal_sig) parts <- c(parts, sprintf(
        "observed range %s differs from battery modal %s", sigs[i], modal_sig))
      message <- paste(parts, collapse = "; ")
    } else if (!is.na(med_r) && abs(med_r) < opts$corr_floor) {
      status <- "weak"
      message <- sprintf("median sibling r=%.3f below floor %.2f", med_r,
                         opts$corr_floor)
    } else {
      status <- "ok"
      message <- sprintf("coheres with battery (median r=%.3f vs %d siblings)",
                         med_r, k)
    }

    rows[[i]] <- tibble(
      survey = meta$survey,
      battery_id = meta$battery_id,
      battery_source = meta$battery_source,
      stem_excerpt = meta$stem_excerpt,
      wave = meta$wave,
      variable = members[i],
      battery_size = m,
      n = item_ns[i],
      k_siblings = k,
      median_sibling_r = med_r,
      item_mean = item_means[i],
      battery_median_mean = batt_med,
      robust_z = z,
      scale_sig = sigs[i],
      neg_corr = neg,
      mean_outlier = outlier,
      status = status,
      message = message
    )
  }
  bind_rows(rows)
}

.skip_row <- function(meta, variable, reason) {
  tibble(
    survey = meta$survey, battery_id = meta$battery_id,
    battery_source = meta$battery_source, stem_excerpt = meta$stem_excerpt,
    wave = meta$wave, variable = variable,
    battery_size = NA_integer_, n = NA_integer_, k_siblings = NA_integer_,
    median_sibling_r = NA_real_, item_mean = NA_real_,
    battery_median_mean = NA_real_, robust_z = NA_real_,
    scale_sig = NA_character_, neg_corr = NA, mean_outlier = NA,
    status = "skip", message = reason
  )
}


# ---------------------------------------------------------------------------
# Public: pure compute step for one survey.
# ---------------------------------------------------------------------------
compute_battery_coherence <- function(survey,
                                      harmonized = NULL,
                                      verbatim = NULL,
                                      batteries = NULL,
                                      concept_map = NULL,
                                      use_concept_fallback = TRUE,
                                      corr_floor = .BATTERY_DEFAULTS$corr_floor,
                                      z_cutoff = .BATTERY_DEFAULTS$z_cutoff,
                                      min_pair_n = .BATTERY_DEFAULTS$min_pair_n,
                                      min_size = .BATTERY_DEFAULTS$min_size,
                                      dev_fallback = .BATTERY_DEFAULTS$dev_fallback) {
  opts <- list(corr_floor = corr_floor, z_cutoff = z_cutoff,
               min_pair_n = min_pair_n, min_size = min_size,
               dev_fallback = dev_fallback, mad_eps = .BATTERY_DEFAULTS$mad_eps)

  if (is.null(harmonized)) {
    harmonized <- load_harmonized_for_survey(survey, .find_harmonized_path(survey))
  }
  if (!"wave" %in% names(harmonized)) {
    stop(sprintf("harmonized output for '%s' has no 'wave' column", survey),
         call. = FALSE)
  }
  wk <- .canon_wave(harmonized$wave)
  wave_labels <- tapply(as.character(harmonized$wave), wk, function(x) x[1])

  if (is.null(batteries)) {
    if (is.null(verbatim)) verbatim <- load_verbatim_items(survey)
    stem_b <- build_stem_batteries(verbatim, min_size = min_size)
    concept_b <- if (use_concept_fallback) {
      build_concept_batteries(survey, harmonized,
                              exclude = unique(stem_b$variable),
                              concept_map = concept_map, min_size = min_size)
    } else {
      stem_b[0, ]
    }
    batteries <- bind_rows(stem_b, concept_b)
  }
  if (nrow(batteries) == 0) {
    return(.skip_row(list(survey = survey, battery_id = NA_character_,
                          battery_source = NA_character_,
                          stem_excerpt = NA_character_, wave = NA_character_),
                     NA_character_,
                     "no batteries derivable (no verbatim stems, no concept groups)"))
  }

  out <- list()
  for (bid in unique(batteries$battery_id)) {
    b <- batteries[batteries$battery_id == bid, , drop = FALSE]
    b_waves <- if (all(is.na(b$wave_key))) {
      # Concept batteries: evaluate on every harmonized wave.
      sort(unique(wk))
    } else {
      unique(b$wave_key)
    }
    members_all <- unique(b$variable)

    for (w in b_waves) {
      # Display wave: stem batteries carry the verbatim key ("w3"); concept
      # batteries (wave = NA) show the harmonized output's own label.
      display_wave <- if (!is.na(b$wave[1])) {
        b$wave[1]
      } else if (w %in% names(wave_labels)) {
        unname(wave_labels[[w]])
      } else {
        as.character(w)
      }
      meta <- list(
        survey = survey, battery_id = bid,
        battery_source = b$battery_source[1], stem_excerpt = b$stem_excerpt[1],
        wave = display_wave
      )
      if (!w %in% wk) {
        out[[length(out) + 1]] <- .skip_row(
          meta, NA_character_,
          sprintf("wave key '%s' not present in harmonized output", w))
        next
      }
      sub <- harmonized[wk == w, , drop = FALSE]

      absent <- setdiff(members_all, names(sub))
      for (v in absent) {
        out[[length(out) + 1]] <- .skip_row(meta, v, "variable not in harmonized output")
      }
      present <- setdiff(members_all, absent)
      has_data <- present[vapply(present,
                                 function(v) sum(!is.na(sub[[v]])) > 0, logical(1))]
      for (v in setdiff(present, has_data)) {
        out[[length(out) + 1]] <- .skip_row(meta, v, "no data in this wave")
      }
      if (length(has_data) < min_size) {
        out[[length(out) + 1]] <- .skip_row(
          meta, NA_character_,
          sprintf("only %d member(s) with data (< %d) in this wave",
                  length(has_data), min_size))
        next
      }
      out[[length(out) + 1]] <- .battery_wave_rows(sub, has_data, meta, opts)
    }
  }
  bind_rows(out)
}


# ---------------------------------------------------------------------------
# Run + write CSV + summary.
# ---------------------------------------------------------------------------
run_battery_coherence <- function(survey, output_dir = NULL, ...) {
  if (is.null(output_dir)) output_dir <- here::here("audit", "reports", survey)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  results <- compute_battery_coherence(survey, ...)
  csv_path <- file.path(output_dir, "04-battery-coherence.csv")
  utils::write.csv(results, csv_path, row.names = FALSE)

  status_levels <- c("ok", "hint", "weak", "na", "skip")
  counts <- as.list(table(factor(results$status, levels = status_levels)))
  n_batt <- length(unique(results$battery_id[!is.na(results$battery_id)]))

  cat(sprintf("\n[battery coherence] survey=%s\n", survey))
  cat(sprintf("  batteries: %d | item-wave rows: %d (ok=%d, hint=%d, weak=%d, na=%d, skip=%d)\n",
              n_batt, nrow(results),
              counts$ok %||% 0, counts$hint %||% 0, counts$weak %||% 0,
              counts$na %||% 0, counts$skip %||% 0))
  cat(sprintf("  CSV: %s\n", csv_path))

  hints <- results[results$status == "hint", , drop = FALSE]
  if (nrow(hints) > 0) {
    cat(sprintf("\n  %d HINT row(s) — possible direction bugs (soft; cross-check\n", nrow(hints)))
    cat("  against 04-label-reconciliation.csv and 04-anchors.csv before acting):\n")
    by_var <- split(hints, hints$variable)
    for (v in names(by_var)) {
      h <- by_var[[v]]
      cat(sprintf("    %-32s %s wave(s): %s | median r: %s\n",
                  v, h$battery_source[1],
                  paste(h$wave, collapse = ","),
                  paste(sprintf("%.2f", h$median_sibling_r), collapse = ",")))
    }
  }
  invisible(results)
}

run_all_surveys <- function() {
  supported <- c("abs", "wvs", "lbs", "afro", "arab-barometer", "kamos",
                 "kgss", "kipa_corruption", "kinu", "ipus", "gcb")
  all_results <- list()
  for (survey in supported) {
    res <- tryCatch(run_battery_coherence(survey), error = function(e) {
      cat(sprintf("\n[battery coherence] %s: %s\n", survey, conditionMessage(e)))
      NULL
    })
    if (!is.null(res)) all_results[[survey]] <- res
  }
  invisible(bind_rows(all_results))
}


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL,
              harmonized = NULL)
  i <- 1
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey      <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys") { out$all_surveys <- TRUE;        i <- i + 1; next }
    if (a == "--harmonized")  { out$harmonized  <- argv[i + 1]; i <- i + 2; next }
    if (a == "--output-dir")  { out$output_dir  <- argv[i + 1]; i <- i + 2; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_battery_coherence.R\n",
          "         (--survey <name> | --all-surveys)\n",
          "         [--harmonized <path>] [--output-dir <path>]\n",
          "\nBattery-coherence hints: flags items that correlate negatively with\n",
          "their battery-mates or whose mean is a robust outlier. Batteries come\n",
          "from shared verbatim stem_text, falling back to concept x scale.\n",
          "Soft check: hints only, always exits 0.\n", sep = "")
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
    if (args$all_surveys) {
      run_all_surveys()
    } else {
      harmonized <- if (!is.null(args$harmonized)) {
        load_harmonized_for_survey(args$survey, args$harmonized)
      } else NULL
      run_battery_coherence(args$survey, output_dir = args$output_dir,
                            harmonized = harmonized)
    }
    quit(status = 0)  # soft check, never blocks
  }
}
