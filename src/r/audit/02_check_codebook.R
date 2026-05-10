#!/usr/bin/env Rscript
# src/r/audit/02_check_codebook.R
#
# Layer 2 — Codebook reconciliation diff engine (audit ticket F4).
#
# Reads the per-survey extracted codebook (parquet, schema v1 in
# data/_codebook_schema/codebook_v1.md) and joins it against every YAML claim
# in `src/config/<survey>/harmonize{_validated}/*.yml`. For each
# (variable × wave) the engine performs four checks:
#
#   (a) valid_range  — YAML's qc.valid_range / valid_range_by_wave must
#                      match [min, max] of non-missing codebook codes for
#                      the same (raw_var × wave). Skipped when the
#                      harmonization method is recode / r_function / derive
#                      (the post-harmonization range is allowed to diverge
#                      from the raw range; identity-method specs are the
#                      only ones whose YAML range claim is a claim about
#                      raw codes).
#   (b) missing_codes— Every codebook code with `missing_code_flag = TRUE`
#                      for that (raw_var × wave) must be declared in the
#                      YAML's missing.codes ∪ missing_conventions[<key>].codes.
#                      Undeclared missing codes are a real bug class:
#                      they propagate to harmonized output as if substantive.
#   (c) value_labels — When the YAML declares scale.labels: {code: "..."},
#                      each label must fuzzy-match (case-insensitive
#                      substring after whitespace normalization) the
#                      codebook's response_label for the same response_code.
#   (d) phrase       — When the YAML declares qc.validate.phrase for a
#                      wave, the codebook's question_text must match the
#                      phrase regex (case-insensitive).
#
# Output: audit/reports/<survey>/02-codebook-recon.csv with one row per
# (variable, wave, raw_var, check). Status ∈ {ok, fail, unreconciled,
# skip_method, skip_no_labels, skip_no_phrase}.
#
# CLI:
#   Rscript src/r/audit/02_check_codebook.R --survey kinu
#   Rscript src/r/audit/02_check_codebook.R --survey ipus
#   Rscript src/r/audit/02_check_codebook.R --all-surveys
#   Rscript src/r/audit/02_check_codebook.R --help
#
# Exit codes:
#   0 — all checks pass (or only skip_*)
#   1 — at least one fail row
#   2 — no codebook found (per-survey or globally for --all-surveys)
#
# See audit/01-audit-framework.md §Layer 2 and audit/02-implementation-tickets.md ticket F4.

suppressPackageStartupMessages({
  library(yaml)
  library(dplyr)
  library(tibble)
  library(here)
  library(arrow)
})

here::i_am("src/r/audit/02_check_codebook.R")

source(here::here("src/r/utils/spec_discovery.R"))


# Surveys recognized by --all-surveys. Mirrors src/r/audit/05_drift_check.R.
.SUPPORTED_SURVEYS <- c(
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa-corruption", "kinu", "ipus"
)

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# Help text
# ---------------------------------------------------------------------------
.print_help <- function() {
  cat(
    "Usage: Rscript src/r/audit/02_check_codebook.R --survey <name>\n",
    "       Rscript src/r/audit/02_check_codebook.R --all-surveys\n",
    "\n",
    "Reconciles every YAML harmonization claim against the per-survey extracted\n",
    "codebook at data/<survey>/codebook/*.parquet (schema v1).\n",
    "\n",
    "  --survey NAME      Survey slug (one of: ",
        paste(.SUPPORTED_SURVEYS, collapse = ", "), ").\n",
    "  --all-surveys      Run for every supported survey with a codebook on disk.\n",
    "  --output-dir PATH  Override output directory (default: audit/reports/<survey>).\n",
    "  -h, --help         Show this message.\n",
    "\n",
    "Exit 0 = all checks pass; 1 = at least one fail; 2 = no codebook found.\n",
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
# Codebook loader (cached).
#
# Reads every parquet in data/<survey>/codebook/, concatenates, and caches
# by survey slug. Per F1, both per-wave files (one per wave) and a single
# cumulative file are valid simultaneously; we glob both shapes.
# ---------------------------------------------------------------------------
.codebook_cache <- new.env(parent = emptyenv())

load_codebook <- function(survey, codebook_dir = NULL, force_reload = FALSE) {
  if (!force_reload && !is.null(.codebook_cache[[survey]])) {
    return(.codebook_cache[[survey]])
  }
  if (is.null(codebook_dir)) {
    codebook_dir <- here::here("data", survey, "codebook")
  }
  if (!dir.exists(codebook_dir)) {
    stop(sprintf(
      "No codebook found at %s. Run the per-survey extractor first.",
      codebook_dir
    ), call. = FALSE)
  }
  files <- list.files(codebook_dir, pattern = "\\.parquet$",
                      full.names = TRUE)
  if (length(files) == 0L) {
    stop(sprintf(
      "No codebook found at %s. Run the per-survey extractor first.",
      codebook_dir
    ), call. = FALSE)
  }

  pieces <- lapply(files, function(f) {
    df <- tryCatch(
      as.data.frame(arrow::read_parquet(f)),
      error = function(e) {
        warning(sprintf("[codebook] cannot read %s: %s", f,
                        conditionMessage(e)), call. = FALSE)
        NULL
      }
    )
    df
  })
  pieces <- pieces[!vapply(pieces, is.null, logical(1))]
  if (length(pieces) == 0L) {
    stop(sprintf(
      "No codebook found at %s (every parquet failed to read).",
      codebook_dir
    ), call. = FALSE)
  }

  cb <- dplyr::bind_rows(pieces)

  # Required columns per F1.
  required <- c("wave", "raw_var", "response_code", "missing_code_flag")
  missing_cols <- setdiff(required, names(cb))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "Codebook at %s missing required columns: %s",
      codebook_dir, paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
  }

  # Normalize types we'll reason about.
  cb$wave <- as.character(cb$wave)
  cb$raw_var <- as.character(cb$raw_var)
  # response_code is type-flexible per schema; keep as character for joining
  # but parse a numeric companion for valid_range arithmetic.
  cb$response_code <- as.character(cb$response_code)
  cb$response_code_num <- suppressWarnings(as.numeric(cb$response_code))
  if (!is.logical(cb$missing_code_flag)) {
    cb$missing_code_flag <- as.logical(cb$missing_code_flag)
  }
  if (!"response_label" %in% names(cb)) cb$response_label <- NA_character_
  if (!"question_text"  %in% names(cb)) cb$question_text  <- NA_character_

  .codebook_cache[[survey]] <- cb
  cb
}


# ---------------------------------------------------------------------------
# Spec helpers
# ---------------------------------------------------------------------------

# Return a list of variable specs (each = the single-variable list inside
# `variables:`), augmented with the parent spec's `missing_conventions:`
# block so each variable is self-contained for downstream reasoning.
.read_spec_variables <- function(spec_path) {
  sp <- tryCatch(yaml::read_yaml(spec_path), error = function(e) NULL)
  if (is.null(sp) || is.null(sp$variables)) return(list())
  conventions <- sp$missing_conventions %||% list()
  vars <- lapply(sp$variables, function(v) {
    v$.spec_path <- spec_path
    v$.conventions <- conventions
    v
  })
  vars
}


# Resolve the harmonization method for a (variable × wave). Mirrors the
# resolution rules used by the harmonize engine: by_wave > exceptions >
# wave-keys > default.
.resolve_method_for_wave <- function(var_spec, wave) {
  h <- var_spec$harmonize %||% list()
  rule <- h$by_wave[[wave]] %||% h$exceptions[[wave]] %||% h[[wave]] %||% h$default
  if (is.null(rule)) return(NA_character_)
  rule$method %||% NA_character_
}


# Resolve the YAML's claim of valid_range for a wave. Returns numeric c(min,max)
# or NULL if not declared.
.resolve_valid_range <- function(var_spec, wave) {
  qc <- var_spec$qc %||% list()
  by_wave <- qc$valid_range_by_wave %||% list()
  if (!is.null(by_wave[[wave]])) {
    rng <- as.numeric(by_wave[[wave]])
    if (length(rng) == 2L && all(is.finite(rng))) return(rng)
  }
  if (!is.null(qc$valid_range)) {
    rng <- as.numeric(qc$valid_range)
    if (length(rng) == 2L && all(is.finite(rng))) return(rng)
  }
  NULL
}


# Resolve the union of missing codes the YAML declares for this variable
# (variable-level explicit codes ∪ named convention from the spec). Returns
# numeric vector (possibly length 0).
.resolve_declared_missing_codes <- function(var_spec) {
  m <- var_spec$missing %||% list()
  codes <- numeric(0)
  if (!is.null(m$codes)) {
    codes <- c(codes, suppressWarnings(as.numeric(m$codes)))
  }
  if (!is.null(m$use_convention)) {
    conv <- var_spec$.conventions[[m$use_convention]]
    if (!is.null(conv)) {
      # Convention can be a bare list of codes or an object {codes:, description:}.
      if (is.list(conv) && !is.null(conv$codes)) {
        codes <- c(codes, suppressWarnings(as.numeric(conv$codes)))
      } else if (is.atomic(conv)) {
        codes <- c(codes, suppressWarnings(as.numeric(conv)))
      }
    }
  }
  codes <- codes[is.finite(codes)]
  unique(codes)
}


# Resolve the YAML scale.labels block for fuzzy comparison. Returns a named
# character vector keyed by stringified code, value = label. NULL if absent.
.resolve_scale_labels <- function(var_spec) {
  scale <- var_spec$scale %||% list()
  labs <- scale$labels
  if (is.null(labs) || length(labs) == 0L) return(NULL)
  out <- character(length(labs))
  nms <- names(labs)
  if (is.null(nms)) {
    # Unnamed list — can't compare without code keys.
    return(NULL)
  }
  for (i in seq_along(labs)) {
    out[i] <- as.character(labs[[i]])
  }
  names(out) <- as.character(nms)
  out
}


# Resolve declared phrase for a wave from qc.validate (list of {waves, phrase}).
# Returns character scalar (regex-ready) or NULL.
.resolve_validate_phrase <- function(var_spec, wave) {
  qc <- var_spec$qc %||% list()
  v <- qc$validate
  if (is.null(v) || length(v) == 0L) return(NULL)
  for (entry in v) {
    waves <- as.character(entry$waves %||% character(0))
    if (wave %in% waves && !is.null(entry$phrase) && nzchar(entry$phrase)) {
      return(as.character(entry$phrase))
    }
  }
  NULL
}


# ---------------------------------------------------------------------------
# Fuzzy label match: case-insensitive substring after whitespace normalization.
# Returns TRUE if the YAML's claimed label is "compatible" with the codebook
# label.
#
# Direction: claimed must be a substring of observed, OR equal after
# normalization. Codebook labels often carry extra context ("1 = Strongly
# agree (강한 동의)") that the YAML's bare label ("Strongly agree") should
# match into. The reverse (claimed-extends-observed) would let "Verry Low"
# match codebook "Low" — that's a typo we WANT to catch.
# ---------------------------------------------------------------------------
.label_match <- function(claimed, observed) {
  if (is.na(claimed) || is.na(observed)) return(FALSE)
  norm <- function(s) {
    s <- tolower(as.character(s))
    s <- gsub("\\s+", " ", s)
    trimws(s)
  }
  c <- norm(claimed); o <- norm(observed)
  if (!nzchar(c) || !nzchar(o)) return(FALSE)
  if (identical(c, o)) return(TRUE)
  grepl(c, o, fixed = TRUE)
}


# ---------------------------------------------------------------------------
# Per-(variable × wave) check generator. Returns a tibble of 0+ rows.
#
# When the raw_var is not in the codebook for this wave, emits a single
# `unreconciled` row (check = "valid_range" by convention so callers can
# tally one row per (variable, wave) for coverage).
# ---------------------------------------------------------------------------
.check_var_wave <- function(var_spec, wave, raw_var, codebook) {
  variable <- var_spec$id

  # Slice codebook to (raw_var × wave). Codebook raw_var is case-preserved
  # per schema; YAML source is also case-preserved. We compare exactly first
  # and then fall back to case-insensitive (some surveys mix `country`/`COUNTRY`).
  slice <- codebook[codebook$wave == wave & codebook$raw_var == raw_var, ,
                    drop = FALSE]
  if (nrow(slice) == 0L) {
    slice <- codebook[
      codebook$wave == wave &
        tolower(codebook$raw_var) == tolower(raw_var), ,
      drop = FALSE
    ]
  }

  if (nrow(slice) == 0L) {
    return(tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "valid_range", status = "unreconciled",
      observed = NA_character_, claimed = NA_character_,
      message = sprintf(
        "raw var '%s' not in extracted codebook for wave '%s'", raw_var, wave
      )
    ))
  }

  rows <- list()

  # ----- (a) valid_range ---------------------------------------------------
  # ARCHITECTURAL DECISION: We only enforce the YAML's valid_range claim
  # against the raw codebook when method == identity. For recode /
  # r_function / derive methods, the YAML's valid_range describes the
  # POST-harmonization range, which can legitimately differ from the raw
  # codes (e.g., IPUS uni_timing collapses raw 4+5 → harmonized 4 and maps
  # raw 6 → harmonized 5, so raw codes are 1-6 but YAML range is [1,5]).
  # Skipping with `skip_method` keeps the check honest about what it can
  # actually verify from the codebook alone. A future ticket could reuse
  # the recoding registry (A4) to apply the recode mapping to raw codes
  # before comparing — but that's outside F4's scope.
  method <- .resolve_method_for_wave(var_spec, wave)
  claimed_range <- .resolve_valid_range(var_spec, wave)

  if (is.null(claimed_range)) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "valid_range", status = "skip_no_labels",
      observed = NA_character_, claimed = NA_character_,
      message = "YAML declares no valid_range / valid_range_by_wave"
    )
  } else if (!is.na(method) && method != "identity") {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "valid_range", status = "skip_method",
      observed = NA_character_,
      claimed = sprintf("[%g, %g]", claimed_range[1], claimed_range[2]),
      message = sprintf(
        "method='%s'; raw range may legitimately differ from harmonized range",
        method
      )
    )
  } else {
    non_missing <- slice[!isTRUE_vec(slice$missing_code_flag) &
                           !is.na(slice$response_code_num), , drop = FALSE]
    if (nrow(non_missing) == 0L) {
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "valid_range", status = "unreconciled",
        observed = NA_character_,
        claimed = sprintf("[%g, %g]", claimed_range[1], claimed_range[2]),
        message = "no non-missing numeric codes in codebook to derive range"
      )
    } else {
      observed_min <- min(non_missing$response_code_num, na.rm = TRUE)
      observed_max <- max(non_missing$response_code_num, na.rm = TRUE)
      observed_str <- sprintf("[%g, %g]", observed_min, observed_max)
      claimed_str <- sprintf("[%g, %g]", claimed_range[1], claimed_range[2])
      ok <- isTRUE(all.equal(observed_min, claimed_range[1])) &&
            isTRUE(all.equal(observed_max, claimed_range[2]))
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "valid_range",
        status = if (ok) "ok" else "fail",
        observed = observed_str,
        claimed = claimed_str,
        message = if (ok) "" else sprintf(
          "raw codebook range %s differs from YAML claim %s (method=identity)",
          observed_str, claimed_str
        )
      )
    }
  }

  # ----- (b) missing_codes -------------------------------------------------
  missing_in_cb <- slice[isTRUE_vec(slice$missing_code_flag) &
                           !is.na(slice$response_code_num), , drop = FALSE]
  observed_missing <- sort(unique(missing_in_cb$response_code_num))
  declared_missing <- sort(unique(.resolve_declared_missing_codes(var_spec)))
  undeclared <- setdiff(observed_missing, declared_missing)

  observed_missing_str <- if (length(observed_missing) == 0L) "[]"
                          else sprintf("[%s]", paste(observed_missing, collapse = ", "))
  claimed_missing_str  <- if (length(declared_missing) == 0L) "[]"
                          else sprintf("[%s]", paste(declared_missing, collapse = ", "))

  if (length(observed_missing) == 0L) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "missing_codes", status = "ok",
      observed = "[]", claimed = claimed_missing_str,
      message = "no missing codes in codebook"
    )
  } else if (length(undeclared) == 0L) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "missing_codes", status = "ok",
      observed = observed_missing_str, claimed = claimed_missing_str,
      message = "all codebook missing codes are declared in YAML"
    )
  } else {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "missing_codes", status = "fail",
      observed = observed_missing_str, claimed = claimed_missing_str,
      message = sprintf(
        "missing codes in codebook not declared in YAML: [%s]",
        paste(undeclared, collapse = ", ")
      )
    )
  }

  # ----- (c) value_labels --------------------------------------------------
  yaml_labels <- .resolve_scale_labels(var_spec)
  if (is.null(yaml_labels) || length(yaml_labels) == 0L) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "value_labels", status = "skip_no_labels",
      observed = NA_character_, claimed = NA_character_,
      message = "YAML declares no scale.labels"
    )
  } else {
    # For each (claimed_code, claimed_label), look up codebook label.
    # Aggregate fail messages so each (variable × wave) yields one row.
    mismatches <- character(0)
    not_in_cb <- character(0)
    for (code in names(yaml_labels)) {
      claimed_label <- yaml_labels[[code]]
      cb_match <- slice[slice$response_code == code, , drop = FALSE]
      if (nrow(cb_match) == 0L) {
        not_in_cb <- c(not_in_cb, sprintf("%s='%s'", code, claimed_label))
        next
      }
      observed_label <- cb_match$response_label[1]
      if (!.label_match(claimed_label, observed_label)) {
        mismatches <- c(mismatches, sprintf(
          "%s: claimed='%s' / codebook='%s'",
          code, claimed_label,
          if (is.na(observed_label)) "<NA>" else observed_label
        ))
      }
    }
    if (length(mismatches) == 0L && length(not_in_cb) == 0L) {
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "value_labels", status = "ok",
        observed = NA_character_, claimed = NA_character_,
        message = sprintf("all %d declared labels match codebook",
                          length(yaml_labels))
      )
    } else if (length(mismatches) > 0L) {
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "value_labels", status = "fail",
        observed = paste(mismatches, collapse = "; "),
        claimed = paste(sprintf("%s='%s'",
                                names(yaml_labels), unname(yaml_labels)),
                        collapse = "; "),
        message = sprintf("%d label mismatch(es): %s",
                          length(mismatches),
                          paste(mismatches, collapse = "; "))
      )
    } else {
      # Only "not in codebook" cases — soft-fail as unreconciled.
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "value_labels", status = "unreconciled",
        observed = NA_character_,
        claimed = paste(not_in_cb, collapse = "; "),
        message = sprintf("declared codes not in codebook for this wave: %s",
                          paste(not_in_cb, collapse = ", "))
      )
    }
  }

  # ----- (d) phrase --------------------------------------------------------
  phrase <- .resolve_validate_phrase(var_spec, wave)
  if (is.null(phrase)) {
    rows[[length(rows) + 1L]] <- tibble(
      variable = variable, wave = wave, raw_var = raw_var,
      check = "phrase", status = "skip_no_phrase",
      observed = NA_character_, claimed = NA_character_,
      message = "YAML declares no qc.validate.phrase for this wave"
    )
  } else {
    qtexts <- unique(slice$question_text[!is.na(slice$question_text)])
    if (length(qtexts) == 0L) {
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "phrase", status = "unreconciled",
        observed = NA_character_, claimed = phrase,
        message = "codebook has no question_text for this raw_var/wave"
      )
    } else {
      hit <- any(vapply(qtexts, function(q) {
        grepl(phrase, q, ignore.case = TRUE, perl = TRUE)
      }, logical(1)))
      observed_str <- if (length(qtexts) == 1L) qtexts[1]
                      else paste(qtexts, collapse = " || ")
      rows[[length(rows) + 1L]] <- tibble(
        variable = variable, wave = wave, raw_var = raw_var,
        check = "phrase",
        status = if (hit) "ok" else "fail",
        observed = observed_str,
        claimed = phrase,
        message = if (hit) "phrase regex matches codebook question_text" else
                  sprintf("phrase regex '/%s/i' does not match codebook question_text",
                          phrase)
      )
    }
  }

  bind_rows(rows)
}


# Defensive isTRUE for a vector of logicals possibly containing NA. Returns
# a logical vector of the same length.
isTRUE_vec <- function(x) {
  if (is.null(x)) return(logical(0))
  out <- as.logical(x)
  out[is.na(out)] <- FALSE
  out
}


# ---------------------------------------------------------------------------
# Public: compute the full per-survey reconciliation table.
#
# Args:
#   survey: survey slug.
#   codebook: optional pre-loaded codebook tibble; else loaded from disk.
#   spec_paths: optional override list of YAML paths; else discovered.
# ---------------------------------------------------------------------------
compute_codebook_reconciliation <- function(survey, codebook = NULL,
                                             spec_paths = NULL) {
  if (is.null(codebook)) codebook <- load_codebook(survey)
  if (is.null(spec_paths)) spec_paths <- list_survey_specs(survey)

  rows <- list()
  for (sp in spec_paths) {
    vars <- .read_spec_variables(sp)
    for (vs in vars) {
      src <- vs$source
      if (is.null(src)) next
      wave_keys <- names(src)
      for (wk in wave_keys) {
        raw_var <- src[[wk]]
        # Variable absent in this wave: source value is NULL/NA. Skip.
        if (is.null(raw_var) || (length(raw_var) == 1L && is.na(raw_var))) next
        if (!nzchar(as.character(raw_var))) next
        rows[[length(rows) + 1L]] <- .check_var_wave(
          var_spec = vs,
          wave = wk,
          raw_var = as.character(raw_var),
          codebook = codebook
        )
      }
    }
  }
  if (length(rows) == 0L) {
    return(tibble(
      variable = character(0), wave = character(0), raw_var = character(0),
      check = character(0), status = character(0),
      observed = character(0), claimed = character(0), message = character(0)
    ))
  }
  bind_rows(rows)
}


# ---------------------------------------------------------------------------
# Public: orchestrator — load + compute + write CSV + summarize.
# Returns the result tibble (invisible) AND sets a status_summary attribute
# the CLI uses to set exit code.
# ---------------------------------------------------------------------------
run_codebook_reconciliation <- function(survey, codebook = NULL,
                                         spec_paths = NULL,
                                         output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  cat(sprintf("\n[codebook recon] survey=%s\n", survey))

  results <- compute_codebook_reconciliation(survey, codebook = codebook,
                                              spec_paths = spec_paths)

  csv_path <- file.path(output_dir, "02-codebook-recon.csv")
  utils::write.csv(results, csv_path, row.names = FALSE, na = "")

  status_levels <- c("ok", "fail", "unreconciled",
                     "skip_method", "skip_no_labels", "skip_no_phrase")
  counts <- if (nrow(results) > 0L) {
    as.list(table(factor(results$status, levels = status_levels)))
  } else {
    setNames(as.list(rep(0L, length(status_levels))), status_levels)
  }

  total <- nrow(results)
  cat(sprintf("  total checks:   %d\n", total))
  for (s in status_levels) {
    v <- counts[[s]]
    cat(sprintf("    %-16s %d\n", s, if (is.null(v)) 0L else as.integer(v)))
  }
  cat(sprintf("  output: %s\n", csv_path))

  fails <- results[results$status == "fail", , drop = FALSE]
  if (nrow(fails) > 0L) {
    top_n <- min(10L, nrow(fails))
    cat(sprintf("\n  *** %d FAIL row(s) — top %d shown:\n",
                nrow(fails), top_n))
    show <- fails[seq_len(top_n),
                  c("variable", "wave", "raw_var", "check", "message"),
                  drop = FALSE]
    print(as.data.frame(show), row.names = FALSE)
    cat("\n  Each fail row is a real Layer 2 audit finding.\n",
        "  See ", csv_path, " for the full set.\n", sep = "")
  }

  attr(results, "n_fail") <- as.integer(counts$fail %||% 0L)
  invisible(results)
}


# ---------------------------------------------------------------------------
# CLI main
# ---------------------------------------------------------------------------
.main <- function(argv) {
  args <- .parse_cli_args(argv)

  if (args$all_surveys) {
    surveys <- .SUPPORTED_SURVEYS
    cat(sprintf("[codebook recon] running for %d surveys: %s\n",
                length(surveys), paste(surveys, collapse = ", ")))
    any_fail <- FALSE
    any_codebook <- FALSE
    for (s in surveys) {
      tryCatch({
        res <- run_codebook_reconciliation(survey = s, output_dir = args$output_dir)
        any_codebook <- TRUE
        if (isTRUE(attr(res, "n_fail") > 0L)) any_fail <- TRUE
      }, error = function(e) {
        msg <- conditionMessage(e)
        cat(sprintf("\n[codebook recon] survey '%s' SKIPPED: %s\n", s, msg))
      })
    }
    if (!any_codebook) quit(status = 2L)
    quit(status = if (any_fail) 1L else 0L)
  }

  if (!(args$survey %in% .SUPPORTED_SURVEYS)) {
    # Allow arbitrary survey slugs (synthetic-test friendly) but warn.
    warning(sprintf("survey '%s' not in supported list: %s",
                    args$survey, paste(.SUPPORTED_SURVEYS, collapse = ", ")),
            call. = FALSE)
  }

  res <- tryCatch(
    run_codebook_reconciliation(survey = args$survey, output_dir = args$output_dir),
    error = function(e) {
      msg <- conditionMessage(e)
      cat(sprintf("\n[codebook recon] ERROR: %s\n", msg))
      if (grepl("^No codebook found", msg)) quit(status = 2L)
      quit(status = 1L)
    }
  )
  n_fail <- as.integer(attr(res, "n_fail") %||% 0L)
  quit(status = if (n_fail > 0L) 1L else 0L)
}


if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) == 0L) {
    .print_help()
    quit(status = 1L)
  }
  .main(argv)
}
