#!/usr/bin/env Rscript
# src/r/audit/05_drift_check.R
#
# Layer 5 — Cross-wave continuity / drift-statistic engine (audit ticket G1).
#
# For every (variable × consecutive wave-pair × country) cell in a survey's
# harmonized output, computes a marginal-distribution drift statistic:
#
#   - ordinal / binary / nominal (integer-valued, character-valued) →
#       Total Variation Distance (TVD), bounded [0, 1].
#       TVD = ½ Σ_k |p_w(k) − p_{w+1}(k)|
#   - continuous (numeric, non-integer-valued)                      →
#       Kolmogorov–Smirnov D, bounded [0, 1].
#
# Variable type is read from the YAML spec's `type:` field; specs are
# discovered via `list_survey_specs()` and parsed once per run. Variables
# not declared in any spec fall back to a column-storage heuristic.
#
# Beyond the raw statistic, every kept row carries a `country_pattern`
# classification (G4) summarizing the cross-country shape of the (variable
# × wave-pair) drift: `universal` (all countries shift similarly — likely
# wording / coding break), `country_specific` (some countries shift, others
# don't — likely real political event), `mixed`, `uniform_low` (nothing
# happened), or `single_country` (single-country surveys). G3 (calibration)
# remains separate.
#
# CLI:
#   Rscript src/r/audit/05_drift_check.R --survey abs
#   Rscript src/r/audit/05_drift_check.R --survey kgss
#   Rscript src/r/audit/05_drift_check.R --all-surveys
#   Rscript src/r/audit/05_drift_check.R --help
#
# See audit/01-audit-framework.md §Layer 5 and audit/02-implementation-tickets.md tickets G1, G4.

suppressPackageStartupMessages({
  library(yaml)
  library(dplyr)
  library(tibble)
  library(here)
})

here::i_am("src/r/audit/05_drift_check.R")

# Source shared utilities. We need:
#   - load_harmonized_data()    from 2.5_validate_harmonization.R (E2)
#   - list_survey_specs()       from spec_discovery.R (A3)
# Both are sourced here at module load so the CLI and library use are
# equivalent. validate_harmonization.R sources its own deps (validation.R,
# recoding.R, etc.); pulling those in is acceptable for the diagnostic.
source(here::here("src/r/utils/spec_discovery.R"))
source(here::here("src/r/data_prep_modules/2.5_validate_harmonization.R"))


# ---------------------------------------------------------------------------
# Survey-name -> harmonized-loader survey-key normalizer.
#
# `list_survey_specs()` and `load_harmonized_data()` use the same survey
# slugs that appear under `src/config/<survey>/` and as keys in
# `.SURVEY_HARMONIZED`. Everywhere else in this script we accept the same
# slug. Single source of truth.
# ---------------------------------------------------------------------------
.SUPPORTED_SURVEYS <- c(
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa_corruption", "kinu", "ipus"
)

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------
.print_help <- function() {
  cat(
    "Usage: Rscript src/r/audit/05_drift_check.R --survey <name>\n",
    "       Rscript src/r/audit/05_drift_check.R --all-surveys\n",
    "\n",
    "Computes per-(variable × wave-pair × country) drift statistics from a\n",
    "survey's harmonized output and writes them to audit/reports/<survey>/05-drift.csv.\n",
    "\n",
    "  --survey NAME      Survey slug (one of: ",
        paste(.SUPPORTED_SURVEYS, collapse = ", "), ").\n",
    "  --all-surveys      Run for every supported survey with a harmonized .rds.\n",
    "  --output-dir PATH  Override output directory (default: audit/reports/<survey>).\n",
    "  -h, --help         Show this message.\n",
    "\n",
    "Exit 0 = ran cleanly (drift findings are normal output, not failures).\n",
    "Exit 1 = invalid invocation or unrecoverable I/O error.\n",
    sep = ""
  )
}


# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE, output_dir = NULL)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a %in% c("-h", "--help"))   { .print_help(); quit(status = 0) }
    if (a == "--survey")            { out$survey      <- argv[i + 1L]; i <- i + 2L; next }
    if (a == "--all-surveys")       { out$all_surveys <- TRUE;          i <- i + 1L; next }
    if (a == "--output-dir")        { out$output_dir  <- argv[i + 1L]; i <- i + 2L; next }
    stop(sprintf("unknown argument: %s (see --help)", a), call. = FALSE)
  }
  if (!out$all_surveys && (is.null(out$survey) || !nzchar(out$survey))) {
    stop("--survey <name> or --all-surveys is required (see --help)", call. = FALSE)
  }
  out
}


# ---------------------------------------------------------------------------
# Build a var_id -> type lookup by parsing every YAML spec for the survey.
#
# When the same id appears in multiple specs (rare) we keep the first
# declaration and warn on conflict. Specs that fail to parse are skipped.
# ---------------------------------------------------------------------------
.build_var_type_map <- function(survey) {
  spec_files <- tryCatch(
    list_survey_specs(survey),
    error = function(e) {
      warning(sprintf("[drift] cannot list specs for survey '%s': %s",
                      survey, conditionMessage(e)), call. = FALSE)
      character(0)
    }
  )

  m <- list()  # id -> type (string)
  for (sf in spec_files) {
    sp <- tryCatch(yaml::read_yaml(sf), error = function(e) NULL)
    if (is.null(sp) || is.null(sp$variables)) next
    for (vs in sp$variables) {
      id <- vs$id
      tp <- vs$type
      if (is.null(id) || !nzchar(id) || is.null(tp) || !nzchar(tp)) next
      if (!is.null(m[[id]])) {
        if (!identical(m[[id]], tp)) {
          warning(sprintf(
            "[drift] var_id '%s' declared with conflicting types: '%s' vs '%s' (keeping first: '%s')",
            id, m[[id]], tp, m[[id]]
          ), call. = FALSE)
        }
        next
      }
      m[[id]] <- tp
    }
  }
  m
}


# ---------------------------------------------------------------------------
# Infer a type for variables not declared in any spec.
#
# Heuristic:
#   character                                           -> "nominal"
#   integer-valued numeric (after dropping NA)          -> "ordinal"
#   numeric with non-integer values                     -> "continuous"
#   length-zero / all-NA                                -> NA_character_
#
# Only invoked as a fallback. Anything that lands here is reported in the
# CSV's `notes` column so the reviewer can verify.
# ---------------------------------------------------------------------------
.infer_type_from_storage <- function(x) {
  if (length(x) == 0L) return(NA_character_)
  if (is.character(x) || is.factor(x)) return("nominal")
  if (!is.numeric(x)) return(NA_character_)
  v <- x[!is.na(x)]
  if (length(v) == 0L) return(NA_character_)
  # Integer-valued? (treat values within 1e-9 of an integer as integer)
  if (all(abs(v - round(v)) < 1e-9)) return("ordinal")
  "continuous"
}


# ---------------------------------------------------------------------------
# Wave-key construction.
#
# Produces a list of consecutive (wave_from, wave_to) pairs in the order
# they should be reported. Sorted by the numeric component of the wave
# string when available; otherwise alphabetically.
#
# Returns: list of length-2 character vectors c(wave_from, wave_to). Each
# wave string is the LABEL we want to show in the CSV (e.g. "w1", "w2003",
# "w2", "y1995"). The matching value in the harmonized data is held in
# `wave_id_map[[label]]`.
# ---------------------------------------------------------------------------
.build_wave_pairs <- function(harmonized_wave_col) {
  uniq <- unique(harmonized_wave_col)
  uniq <- uniq[!is.na(uniq)]
  if (length(uniq) < 2L) return(list())

  # Build (label, sort_key, harmonized_value) for every unique wave.
  # ABS stores integer waves; we relabel to "w1".."w6" for output clarity.
  if (is.numeric(uniq)) {
    labels <- paste0("w", as.integer(uniq))
    keys <- as.numeric(uniq)
    map <- as.list(setNames(uniq, labels))
  } else {
    labels <- as.character(uniq)
    # Extract numeric component for sort; non-numeric strings get NA, then
    # sort alphabetically as a fallback below.
    num_extract <- regmatches(labels, regexpr("[0-9]+", labels))
    keys <- suppressWarnings(as.numeric(
      ifelse(nzchar(num_extract), num_extract, NA)
    ))
    # Stable secondary sort by label text for waves like "w2019a"/"w2019b".
    map <- as.list(setNames(uniq, labels))
  }

  ord <- if (any(!is.na(keys))) order(keys, labels) else order(labels)
  labels <- labels[ord]
  keys   <- keys[ord]

  pairs <- vector("list", length(labels) - 1L)
  for (i in seq_len(length(labels) - 1L)) {
    pairs[[i]] <- list(
      from_label = labels[i],
      to_label   = labels[i + 1L],
      from_value = map[[labels[i]]],
      to_value   = map[[labels[i + 1L]]]
    )
  }
  pairs
}


# ---------------------------------------------------------------------------
# Ordinal / nominal TVD between two NA-stripped vectors. Both vectors are
# coerced to character before tabulating so character-vs-integer mixing
# (rare but possible) doesn't silently widen the level set.
# ---------------------------------------------------------------------------
.compute_tvd <- function(x, y) {
  xc <- as.character(x[!is.na(x)])
  yc <- as.character(y[!is.na(y)])
  nx <- length(xc); ny <- length(yc)
  if (nx == 0L || ny == 0L) return(NA_real_)
  levels <- sort(unique(c(xc, yc)))
  px <- tabulate(match(xc, levels), nbins = length(levels)) / nx
  py <- tabulate(match(yc, levels), nbins = length(levels)) / ny
  0.5 * sum(abs(px - py))
}


# ---------------------------------------------------------------------------
# Continuous KS-D between two NA-stripped vectors.
# Wraps ks.test() in a defensive tryCatch (KS warns on ties; we suppress).
# ---------------------------------------------------------------------------
.compute_ks_d <- function(x, y) {
  xv <- as.numeric(x[!is.na(x)])
  yv <- as.numeric(y[!is.na(y)])
  nx <- length(xv); ny <- length(yv)
  if (nx == 0L || ny == 0L) return(NA_real_)
  res <- tryCatch(
    suppressWarnings(stats::ks.test(xv, yv)),
    error = function(e) NULL
  )
  if (is.null(res)) return(NA_real_)
  unname(res$statistic)
}


# ---------------------------------------------------------------------------
# Compute a single (variable × wave-pair × country) cell.
#
# Returns: tibble with one row, OR a one-row "skip" tibble when the cell
# fails preconditions (n < 30 either side, all-NA, etc.). Skip rows have
# `statistic = NA` and a `notes` field describing the reason — they're
# excluded from the CSV but counted for the stdout summary.
#
# Args:
#   x_from, x_to: vectors of the variable in each wave (already filtered
#                 to country, possibly with NAs).
#   var          : harmonized var name (string)
#   var_type     : one of "ordinal", "nominal", "continuous" (or NA)
#   wave_from    : label
#   wave_to      : label
#   country      : country label or "<pooled>"
#   min_n        : minimum non-NA observations required per side
# ---------------------------------------------------------------------------
.compute_cell <- function(x_from, x_to, var, var_type, wave_from, wave_to,
                          country, min_n = 30L) {
  n_from <- sum(!is.na(x_from))
  n_to   <- sum(!is.na(x_to))

  if (n_from < min_n || n_to < min_n) {
    return(tibble(
      variable = var, type = var_type,
      wave_from = wave_from, wave_to = wave_to,
      country = country, n_from = n_from, n_to = n_to,
      statistic = NA_real_, stat_type = NA_character_,
      notes = sprintf("skipped: n<%d (n_from=%d, n_to=%d)", min_n, n_from, n_to)
    ))
  }

  # If we don't know the type, infer from storage of the combined vector.
  effective_type <- var_type
  if (is.na(effective_type) || !nzchar(effective_type)) {
    effective_type <- .infer_type_from_storage(c(x_from, x_to))
  }

  if (is.na(effective_type)) {
    return(tibble(
      variable = var, type = NA_character_,
      wave_from = wave_from, wave_to = wave_to,
      country = country, n_from = n_from, n_to = n_to,
      statistic = NA_real_, stat_type = NA_character_,
      notes = "skipped: type cannot be inferred"
    ))
  }

  if (effective_type == "continuous") {
    s <- .compute_ks_d(x_from, x_to)
    stat_type <- "KS-D"
  } else if (effective_type %in% c("nominal", "categorical")) {
    # Treat each label/level as a category. Specs use "categorical" as a
    # synonym for nominal (~24 vars across surveys); fold it in here.
    s <- .compute_tvd(x_from, x_to)
    stat_type <- "TVD-nominal"
  } else {
    # Default: ordinal / binary / anything else integer-coded. `binary` is
    # an ordinal-with-2-levels for our purposes.
    s <- .compute_tvd(x_from, x_to)
    stat_type <- "TVD"
  }

  type_note <- if (is.na(var_type) || !nzchar(var_type)) {
    sprintf("type inferred=%s", effective_type)
  } else {
    NA_character_
  }

  tibble(
    variable = var, type = effective_type,
    wave_from = wave_from, wave_to = wave_to,
    country = country, n_from = n_from, n_to = n_to,
    statistic = s, stat_type = stat_type,
    notes = type_note %||% NA_character_
  )
}


# ---------------------------------------------------------------------------
# Iterate over a variable × wave-pair, computing per-country and pooled.
#
# Returns a tibble of (kept rows + skip rows). Skip rows are filtered out
# of the CSV by the caller; they're returned so the caller can tabulate
# the skip-reason distribution for the stdout summary.
# ---------------------------------------------------------------------------
.sweep_variable_pair <- function(d_from, d_to, var, var_type,
                                 wave_from, wave_to, has_country,
                                 min_n = 30L) {
  rows <- list()

  # Skip variables entirely missing in either wave.
  if (!var %in% names(d_from) || !var %in% names(d_to)) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = var, type = var_type,
      wave_from = wave_from, wave_to = wave_to,
      country = "<pooled>", n_from = 0L, n_to = 0L,
      statistic = NA_real_, stat_type = NA_character_,
      notes = "skipped: variable absent in one or both waves"
    )
    return(bind_rows(rows))
  }

  # Skip variables fully NA in either wave.
  if (all(is.na(d_from[[var]])) || all(is.na(d_to[[var]]))) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = var, type = var_type,
      wave_from = wave_from, wave_to = wave_to,
      country = "<pooled>", n_from = sum(!is.na(d_from[[var]])),
      n_to = sum(!is.na(d_to[[var]])),
      statistic = NA_real_, stat_type = NA_character_,
      notes = "skipped: all-NA in one or both waves"
    )
    return(bind_rows(rows))
  }

  # Per-country rows.
  if (has_country) {
    countries <- sort(unique(c(
      as.character(d_from$country[!is.na(d_from$country)]),
      as.character(d_to$country[!is.na(d_to$country)])
    )))
    for (cc in countries) {
      x_from <- d_from[[var]][!is.na(d_from$country) & as.character(d_from$country) == cc]
      x_to   <- d_to[[var]]  [!is.na(d_to$country)   & as.character(d_to$country)   == cc]
      rows[[length(rows) + 1L]] <- .compute_cell(
        x_from, x_to, var = var, var_type = var_type,
        wave_from = wave_from, wave_to = wave_to,
        country = cc, min_n = min_n
      )
    }
  }

  # Pooled-by-country row (always emitted).
  rows[[length(rows) + 1L]] <- .compute_cell(
    d_from[[var]], d_to[[var]], var = var, var_type = var_type,
    wave_from = wave_from, wave_to = wave_to,
    country = "<pooled>", min_n = min_n
  )

  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Country-pattern classifier (audit ticket G4).
#
# For each (variable × wave-pair), looks at the per-country drift values
# (excluding the `<pooled>` row) and classifies the cross-country pattern:
#
#   - single_country : only one country present (single-country surveys
#                      like KGSS, KAMOS, KIPA-corruption, KINU, IPUS).
#   - uniform_low    : nothing happened anywhere — modal case.
#                      median_drift < 0.05 AND sd_drift < 0.05.
#   - universal      : all countries shifted similarly large amounts
#                      (likely wording-change / coding break).
#                      median_drift > 0.05 AND sd/median < 0.4.
#   - country_specific: some countries shifted, others didn't
#                      (likely real political event).
#                      max_drift > 0.20 AND min_drift < 0.10.
#   - mixed          : doesn't fit cleanly into any of the above.
#
# Returns a tibble with columns: variable, wave_from, wave_to, country_pattern.
# The caller joins this onto the per-row drift table (both per-country and
# pooled rows for a given (variable, wave-pair) get the same pattern label).
#
# Skip rows (statistic == NA) are excluded from the per-country aggregation
# but still receive a pattern label via the join (NA-statistic rows for a
# (variable, wave-pair) where some countries DID compute will inherit the
# group's pattern).
# ---------------------------------------------------------------------------
.classify_country_pattern <- function(kept) {
  if (nrow(kept) == 0L) {
    return(tibble(
      variable = character(0), wave_from = character(0),
      wave_to = character(0), country_pattern = character(0)
    ))
  }

  per_country <- kept %>%
    dplyr::filter(.data$country != "<pooled>", !is.na(.data$statistic))

  group_stats <- per_country %>%
    dplyr::group_by(.data$variable, .data$wave_from, .data$wave_to) %>%
    dplyr::summarise(
      n_countries  = dplyr::n(),
      median_drift = stats::median(.data$statistic, na.rm = TRUE),
      sd_drift     = stats::sd(.data$statistic, na.rm = TRUE),
      min_drift    = min(.data$statistic, na.rm = TRUE),
      max_drift    = max(.data$statistic, na.rm = TRUE),
      .groups      = "drop"
    )

  # `sd` returns NA for n=1; treat as 0 for the cv calculation so a one-
  # country group falls into single_country regardless.
  group_stats <- dplyr::mutate(
    group_stats,
    sd_drift = ifelse(is.na(.data$sd_drift), 0, .data$sd_drift),
    cv_drift = .data$sd_drift / pmax(.data$median_drift, 1e-9),
    country_pattern = dplyr::case_when(
      .data$n_countries <= 1L
        ~ "single_country",
      .data$median_drift < 0.05 & .data$sd_drift < 0.05
        ~ "uniform_low",
      .data$median_drift > 0.05 & .data$cv_drift < 0.4
        ~ "universal",
      .data$max_drift > 0.20 & .data$min_drift < 0.10
        ~ "country_specific",
      TRUE
        ~ "mixed"
    )
  )

  # Some (variable, wave-pair) groups exist only as a pooled row (zero
  # per-country rows met the min_n threshold). Those groups are not
  # represented in `group_stats`; they will get NA in the join and we
  # default to "single_country" if the survey itself has no per-country
  # rows, or "mixed" otherwise. The caller decides via has_country.
  dplyr::select(group_stats, "variable", "wave_from", "wave_to", "country_pattern")
}


# ---------------------------------------------------------------------------
# Public: pure compute step.
#
# Args:
#   harmonized: data frame with `wave` (mandatory) and optionally `country`.
#   survey    : survey slug; used only for spec discovery (var-type lookup).
#   min_n     : minimum non-NA observations required per (var × wave × country)
#               cell. Default 30 per ticket spec.
#
# Returns: tibble with one row per cell. Caller applies skip-row filter +
# sort. The returned object includes BOTH kept rows and skip rows; the
# CSV writer filters down to kept rows.
# ---------------------------------------------------------------------------
compute_drift_statistics <- function(harmonized, survey, min_n = 30L) {
  if (!"wave" %in% names(harmonized)) {
    stop("harmonized data has no `wave` column", call. = FALSE)
  }
  has_country <- "country" %in% names(harmonized)

  # Single-country surveys (KGSS, KAMOS, KIPA-corruption, KINU, IPUS) carry
  # a `country` column with a single value (e.g. "KOR"). Per the ticket,
  # only pooled rows should be produced for these — emitting both a
  # per-country and pooled row would just duplicate every line.
  if (has_country) {
    uniq_countries <- unique(harmonized$country[!is.na(harmonized$country)])
    if (length(uniq_countries) <= 1L) {
      has_country <- FALSE
    }
  }

  # Variables to check: every column except wave/country/row_id.
  reserved <- c("wave", "country", "row_id")
  vars <- setdiff(names(harmonized), reserved)
  if (length(vars) == 0L) return(tibble())

  # Variable type lookup.
  type_map <- .build_var_type_map(survey)

  # Pre-compute per-wave subsets so we don't re-filter on every variable.
  pairs <- .build_wave_pairs(harmonized$wave)
  if (length(pairs) == 0L) return(tibble())

  # Cache (wave_value -> data subset).
  wave_subsets <- new.env(parent = emptyenv())
  for (p in pairs) {
    for (val in list(p$from_value, p$to_value)) {
      key <- as.character(val)
      if (is.null(wave_subsets[[key]])) {
        wave_subsets[[key]] <- harmonized[
          !is.na(harmonized$wave) & harmonized$wave == val, ,
          drop = FALSE
        ]
      }
    }
  }

  out <- vector("list", length(vars) * length(pairs))
  k <- 1L
  for (var in vars) {
    var_type <- type_map[[var]] %||% NA_character_
    for (p in pairs) {
      d_from <- wave_subsets[[as.character(p$from_value)]]
      d_to   <- wave_subsets[[as.character(p$to_value)]]
      rows <- .sweep_variable_pair(
        d_from = d_from, d_to = d_to,
        var = var, var_type = var_type,
        wave_from = p$from_label, wave_to = p$to_label,
        has_country = has_country,
        min_n = min_n
      )
      out[[k]] <- rows
      k <- k + 1L
    }
  }

  bind_rows(out)
}


# ---------------------------------------------------------------------------
# Public: orchestrator — load + compute + write CSV + summarize.
# ---------------------------------------------------------------------------
run_drift_check <- function(survey, harmonized = NULL, output_dir = NULL,
                            min_n = 30L) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  if (is.null(harmonized)) {
    harmonized <- load_harmonized_data(survey)
  }

  cat(sprintf("\n[drift check] survey=%s\n", survey))

  results <- compute_drift_statistics(harmonized, survey = survey, min_n = min_n)

  if (nrow(results) == 0L) {
    cat("  (no rows produced — harmonized data has fewer than 2 waves)\n")
    return(invisible(results))
  }

  # Split kept rows from skip rows.
  is_skip <- !is.na(results$notes) & grepl("^skipped:", results$notes)
  kept <- results[!is_skip, , drop = FALSE]
  skipped <- results[is_skip, , drop = FALSE]

  # Country-pattern classification (G4): label every kept row with whether
  # the underlying (variable × wave-pair) shifted universally across
  # countries (likely wording change), only in some countries (likely real
  # political event), or not meaningfully at all. Single-country surveys
  # (only `<pooled>` rows) get `single_country`.
  has_country_rows <- any(kept$country != "<pooled>")
  if (has_country_rows) {
    pattern_lookup <- .classify_country_pattern(kept)
    kept <- dplyr::left_join(
      kept, pattern_lookup,
      by = c("variable", "wave_from", "wave_to")
    )
    # (variable, wave-pair) groups whose per-country rows were all skipped
    # but a pooled row survived inherit `mixed`.
    kept$country_pattern[is.na(kept$country_pattern)] <- "mixed"
  } else {
    kept$country_pattern <- "single_country"
  }

  # Sort kept rows by statistic descending so highest-drift is at the top.
  kept <- kept[order(-kept$statistic, kept$variable, kept$wave_from, kept$country), ,
               drop = FALSE]

  # Reorder columns: country_pattern after country (G4 column order).
  col_order <- c(
    "variable", "type", "wave_from", "wave_to", "country", "country_pattern",
    "n_from", "n_to", "statistic", "stat_type", "notes"
  )
  kept <- kept[, col_order, drop = FALSE]

  csv_path <- file.path(output_dir, "05-drift.csv")
  utils::write.csv(kept, csv_path, row.names = FALSE, na = "")

  # ---- Stdout summary ---------------------------------------------------
  total_cells <- nrow(results)
  n_kept <- nrow(kept)
  n_skipped <- nrow(skipped)

  cat(sprintf("  total cells:         %d\n", total_cells))
  cat(sprintf("  computed (kept):     %d\n", n_kept))
  cat(sprintf("  skipped:             %d\n", n_skipped))

  if (n_skipped > 0L) {
    skip_reason <- sub("^skipped: ", "", skipped$notes)
    # Group reasons coarsely (n<30 family vs absent vs all-NA vs other).
    bucket <- ifelse(grepl("^n<", skip_reason), "insufficient_n",
              ifelse(grepl("^variable absent", skip_reason), "variable_absent",
              ifelse(grepl("^all-NA", skip_reason), "all_NA",
              ifelse(grepl("^type", skip_reason), "type_unknown", "other"))))
    counts <- table(bucket)
    cat("  skip breakdown:\n")
    for (nm in names(counts)) {
      cat(sprintf("    %-18s %d\n", nm, counts[[nm]]))
    }
  }

  distinct_vars <- length(unique(kept$variable))
  cat(sprintf("  distinct variables covered: %d\n", distinct_vars))
  cat(sprintf("  output: %s\n", csv_path))

  # Country-pattern breakdown (G4): one count per (variable × wave-pair)
  # group, not per row. We collapse on (variable, wave_from, wave_to,
  # country_pattern) to avoid double-counting the per-country rows.
  if (n_kept > 0L && "country_pattern" %in% names(kept)) {
    group_patterns <- unique(kept[, c("variable", "wave_from", "wave_to",
                                      "country_pattern"), drop = FALSE])
    pattern_counts <- as.list(table(group_patterns$country_pattern))
    cat("  country_pattern breakdown (var x wave-pair groups):\n")
    for (nm in c("universal", "country_specific", "mixed",
                 "uniform_low", "single_country")) {
      v <- pattern_counts[[nm]]
      cat(sprintf("    %-18s %d\n", nm, if (is.null(v)) 0L else as.integer(v)))
    }
  }

  if (n_kept > 0L) {
    top_n <- min(20L, n_kept)
    top <- kept[seq_len(top_n), c("variable", "type", "wave_from", "wave_to",
                                  "country", "country_pattern",
                                  "n_from", "n_to",
                                  "statistic", "stat_type"),
                drop = FALSE]
    cat(sprintf("\n  Top %d highest-drift rows:\n", top_n))
    print(as.data.frame(top), row.names = FALSE, digits = 4)
  }

  invisible(results)
}


# ---------------------------------------------------------------------------
# CLI main
# ---------------------------------------------------------------------------
.main <- function(argv) {
  args <- .parse_cli_args(argv)

  if (args$all_surveys) {
    surveys <- .SUPPORTED_SURVEYS
    cat(sprintf("[drift check] running for %d surveys: %s\n",
                length(surveys), paste(surveys, collapse = ", ")))
    for (s in surveys) {
      ok <- tryCatch({
        run_drift_check(survey = s, output_dir = args$output_dir)
        TRUE
      }, error = function(e) {
        cat(sprintf("\n[drift check] survey '%s' SKIPPED: %s\n", s, conditionMessage(e)))
        FALSE
      })
    }
    return(invisible(NULL))
  }

  if (!(args$survey %in% .SUPPORTED_SURVEYS)) {
    stop(sprintf(
      "unknown survey '%s'. Supported: %s",
      args$survey, paste(.SUPPORTED_SURVEYS, collapse = ", ")
    ), call. = FALSE)
  }

  run_drift_check(survey = args$survey, output_dir = args$output_dir)
}


if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) == 0L) {
    .print_help()
    quit(status = 1)
  }
  .main(argv)
}
