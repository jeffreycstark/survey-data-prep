#!/usr/bin/env Rscript
# src/r/audit/generate_phase_b_suggestions.R
#
# Suggestions generator for audit Phase B5 (mandatory valid_range) and
# B6 (mandatory qc.validate.phrase for safe_reverse_* rules).
#
# The deferred-work memory (project_audit_phase_b_deferred.md, 2026-05-09)
# specifies an explicit Jeff-review checkpoint: this script does NOT edit
# YAML — it only produces a CSV of suggestions for human review.
#
# Workflow:
#   1. Run this script: writes audit/reports/phase_b_suggestions.csv.
#   2. Jeff opens the CSV, marks each row decision={accept|reject|modify}
#      (with optional revised value).
#   3. A follow-up apply script consumes the reviewed CSV and edits YAML.
#
# Schema of output CSV:
#   survey, spec_file, variable, check, wave, current, suggested, source,
#   justification, decision (blank), revised (blank)

suppressPackageStartupMessages({
  library(yaml)
  library(here)
})

here::i_am("src/r/audit/generate_phase_b_suggestions.R")

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---------------------------------------------------------------------------
# Load the recoding registry — function name → output_scale lookup.
# ---------------------------------------------------------------------------
.load_registry <- function() {
  path <- here::here("src/r/utils/recoding_registry.yml")
  entries <- yaml::read_yaml(path)
  out <- list()
  for (e in entries) {
    if (!is.null(e$fn) && !is.null(e$output_scale)) {
      out[[e$fn]] <- list(
        output_scale = as.numeric(e$output_scale),
        notes = e$notes %||% ""
      )
    }
  }
  out
}

# ---------------------------------------------------------------------------
# Walk every spec file under src/config/<survey>/harmonize/.
# ---------------------------------------------------------------------------
.list_specs <- function() {
  roots <- list.files(here::here("src/config"), full.names = TRUE)
  roots <- roots[grepl("^[^_]", basename(roots))]   # skip _anchors, _schema, etc.
  specs <- list()
  for (r in roots) {
    survey <- basename(r)
    sub_dirs <- list.files(r, full.names = TRUE)
    sub_dirs <- sub_dirs[basename(sub_dirs) == "harmonize"]
    for (d in sub_dirs) {
      yamls <- list.files(d, pattern = "\\.yml$", full.names = TRUE)
      for (y in yamls) {
        specs[[length(specs) + 1L]] <- list(survey = survey, path = y)
      }
    }
  }
  specs
}

# ---------------------------------------------------------------------------
# Collect every fn referenced by a variable across all waves.
# ---------------------------------------------------------------------------
.collect_fns <- function(var_spec) {
  fns <- character(0)
  hz <- var_spec$harmonize %||% list()
  if (!is.null(hz$default$fn)) fns <- c(fns, as.character(hz$default$fn))
  if (!is.null(hz$exceptions)) {
    for (w in names(hz$exceptions)) {
      ex <- hz$exceptions[[w]]
      if (!is.null(ex$fn)) fns <- c(fns, as.character(ex$fn))
    }
  }
  # Some specs use top-level wave keys directly (e.g. w1: {method:...})
  for (k in names(hz)) {
    if (k %in% c("default", "exceptions")) next
    rule <- hz[[k]]
    if (is.list(rule) && !is.null(rule$fn)) fns <- c(fns, as.character(rule$fn))
  }
  unique(fns)
}

# ---------------------------------------------------------------------------
# B5: suggest valid_range when missing.
# ---------------------------------------------------------------------------
.suggest_valid_range <- function(var_spec, registry) {
  qc <- var_spec$qc %||% list()
  if (isTRUE(qc$skip_range_check)) return(NULL)
  if (!is.null(qc$valid_range) || !is.null(qc$valid_range_by_wave)) return(NULL)

  smin <- var_spec$scale$min
  smax <- var_spec$scale$max
  if (!is.null(smin) && !is.null(smax)) {
    return(list(
      suggested = sprintf("[%s, %s]", smin, smax),
      source    = "scale.min / scale.max declared on this variable",
      justification = sprintf(
        "YAML declares scale.min=%s, scale.max=%s. Use as valid_range.",
        smin, smax
      )
    ))
  }

  fns <- .collect_fns(var_spec)
  fn_with_scale <- fns[fns %in% names(registry)]
  if (length(fn_with_scale) > 0L) {
    scales <- vapply(fn_with_scale, function(f) {
      s <- registry[[f]]$output_scale
      if (length(s) == 2) paste(s, collapse = "/") else NA_character_
    }, character(1))
    scales <- scales[!is.na(scales)]
    if (length(unique(scales)) == 1L) {
      pair <- strsplit(scales[1], "/", fixed = TRUE)[[1]]
      return(list(
        suggested = sprintf("[%s, %s]", pair[1], pair[2]),
        source    = sprintf(
          "recoding_registry.yml output_scale for fn(s): %s",
          paste(unique(fn_with_scale), collapse = ", ")
        ),
        justification = sprintf(
          "All recode functions on this variable produce values in [%s, %s].",
          pair[1], pair[2]
        )
      ))
    }
    return(list(
      suggested = "(disagreement)",
      source    = sprintf(
        "recoding_registry.yml output_scale for fn(s): %s",
        paste(unique(fn_with_scale), collapse = ", ")
      ),
      justification = sprintf(
        "Recode functions disagree on output_scale: %s. Needs human pick.",
        paste(unique(scales), collapse = " vs ")
      )
    ))
  }

  list(
    suggested = "(unknown)",
    source    = "no inference available",
    justification = "No scale block and no recode function with a registered output_scale. Manual decision required."
  )
}

# ---------------------------------------------------------------------------
# B6: suggest qc.validate.phrase when missing and a safe_reverse_* fn is used.
# ---------------------------------------------------------------------------
.uses_safe_reverse <- function(fns) {
  any(grepl("^safe_reverse_", fns))
}

.has_validate_phrase <- function(var_spec) {
  validate <- var_spec$qc$validate %||% list()
  if (length(validate) == 0L) return(FALSE)
  if (is.list(validate) && !is.null(names(validate)) && "phrase" %in% names(validate)) {
    return(nzchar(validate$phrase %||% ""))
  }
  for (entry in validate) {
    if (is.list(entry) && !is.null(entry$phrase) && nzchar(entry$phrase)) return(TRUE)
  }
  FALSE
}

.suggest_phrase <- function(var_spec) {
  desc <- as.character(var_spec$description %||% "")
  if (!nzchar(desc)) {
    return(list(
      suggested     = "(unknown)",
      source        = "no description available",
      justification = "Variable lacks a description field. Manual phrase needed."
    ))
  }
  # Strip parenthetical labels & scale notes — keep the substantive noun phrase.
  cleaned <- gsub("\\([^)]*\\)", "", desc)
  cleaned <- gsub("[[:punct:]]", " ", cleaned)
  cleaned <- gsub("\\s+", " ", cleaned)
  cleaned <- trimws(cleaned)
  # Build a regex-friendly suggestion: keep the most distinctive 1-3 nouns.
  tokens <- strsplit(tolower(cleaned), "\\s+")[[1]]
  stop <- c("the","a","an","of","in","on","and","or","to","for","with",
            "trust","scale","scaled","item","items","level","levels",
            "ordinal","binary","continuous","nominal","categorical",
            "higher","lower","more","less","most","least","1","2","3","4",
            "rating","measure","items","item")
  tokens <- tokens[!tokens %in% stop & nchar(tokens) > 2]
  pick <- head(tokens, 3)
  if (length(pick) == 0L) pick <- head(strsplit(tolower(cleaned), "\\s+")[[1]], 1)
  list(
    suggested     = paste(pick, collapse = "|"),
    source        = sprintf("inferred from description: '%s'",
                            substr(desc, 1, 60)),
    justification = "Auto-suggested regex from description noun-tokens. Verify against actual codebook wording."
  )
}

# ---------------------------------------------------------------------------
# Main: collect suggestions and write a CSV.
# ---------------------------------------------------------------------------
.main <- function() {
  registry <- .load_registry()
  specs <- .list_specs()
  rows <- list()
  for (sp in specs) {
    parsed <- tryCatch(yaml::read_yaml(sp$path), error = function(e) NULL)
    if (is.null(parsed) || is.null(parsed$variables)) next
    spec_file <- sub(
      paste0(here::here(), "/"), "", sp$path, fixed = TRUE
    )
    for (v in parsed$variables) {
      var_id <- v$id %||% "(unknown)"

      # B5 — valid_range
      vr_sugg <- .suggest_valid_range(v, registry)
      if (!is.null(vr_sugg)) {
        rows[[length(rows) + 1L]] <- list(
          survey       = sp$survey,
          spec_file    = spec_file,
          variable     = var_id,
          check        = "B5_valid_range",
          wave         = "",
          current      = "(missing)",
          suggested    = vr_sugg$suggested,
          source       = vr_sugg$source,
          justification = vr_sugg$justification,
          decision     = "",
          revised      = ""
        )
      }

      # B6 — qc.validate.phrase for safe_reverse_* users
      fns <- .collect_fns(v)
      if (.uses_safe_reverse(fns) && !.has_validate_phrase(v)) {
        ph_sugg <- .suggest_phrase(v)
        rows[[length(rows) + 1L]] <- list(
          survey       = sp$survey,
          spec_file    = spec_file,
          variable     = var_id,
          check        = "B6_validate_phrase",
          wave         = "",
          current      = "(missing)",
          suggested    = ph_sugg$suggested,
          source       = ph_sugg$source,
          justification = ph_sugg$justification,
          decision     = "",
          revised      = ""
        )
      }
    }
  }

  if (length(rows) == 0L) {
    cat("No B5 or B6 gaps found across project.\n")
    quit(status = 0)
  }

  df <- do.call(rbind, lapply(rows, function(r) as.data.frame(r, stringsAsFactors = FALSE)))
  out_path <- here::here("audit/reports/phase_b_suggestions.csv")
  utils::write.csv(df, out_path, row.names = FALSE, na = "")
  cat(sprintf("Wrote %d suggestion rows -> %s\n", nrow(df), out_path))
  cat("Breakdown by check:\n")
  print(table(df$check))
  cat("Breakdown by survey:\n")
  print(table(df$survey))
}

.main()
