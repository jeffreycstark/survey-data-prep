#!/usr/bin/env Rscript
# src/r/audit/run_all.R
#
# Local audit orchestrator (audit ticket H1).
#
# Single dedicated R script that runs every audit module for every survey
# whose prerequisites are present, then writes a one-page summary to
# audit/SUMMARY.md and prints a five-line tldr to stdout.
#
# This is NOT CI — there are no automated triggers. It is a script the user
# invokes manually when they want a hygiene check. The script is read-only
# on every other audit module: it shells out via `system2("Rscript", ...)`
# to invoke each one with its existing CLI, captures the exit code, parses
# the CSV the module wrote, and tallies status counts.
#
# CLI:
#   Rscript src/r/audit/run_all.R                       # all surveys
#   Rscript src/r/audit/run_all.R --survey abs          # one survey
#   Rscript src/r/audit/run_all.R --quick               # skip G1 (drift) + F4 (codebook)
#   Rscript src/r/audit/run_all.R --verbose             # echo each module's full stdout
#
# Exit codes:
#   0  every module passed cleanly (no fails)
#   1  at least one module reports fails
#   2  prerequisites missing for surveys requested (no harmonization output)
#
# See audit/01-audit-framework.md §Layer 7 / H1 ticket and audit/02-implementation-tickets.md ticket H1.

suppressPackageStartupMessages({
  library(yaml)
  library(here)
})

here::i_am("src/r/audit/run_all.R")

source(here::here("src/r/utils/spec_discovery.R"))
source(here::here("src/r/harmonize/validate_spec.R"))


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
.SUPPORTED_SURVEYS <- c(
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa-corruption", "kinu", "ipus"
)

# Survey slug → harmonized .rds filename. Most surveys map slug-to-filename
# directly, but `arab-barometer` and `kipa-corruption` use underscores in
# the .rds filename. Mirrors load_harmonized_for_survey() in 04_anchor_diagnostic.R
# (which is buggy for hyphenated surveys; we resolve the path ourselves so we
# can detect prerequisites consistently).
.HARMONIZED_PATH <- function(survey) {
  fname <- switch(
    survey,
    `arab-barometer` = "arab_barometer_harmonized.rds",
    `kipa-corruption` = "kipa_corruption_harmonized.rds",
    paste0(survey, "_harmonized.rds")
  )
  here::here("data", "processed", fname)
}

# Anchor files (Layer 4 / D3). The anchor diagnostic itself filters per-survey
# based on each loader's `surveys:` field, but its data loader is the bug
# above — we only run D3 when (a) the harmonized rds exists AND (b) the
# anchor's anchor variable column is present in the harmonized output.
.ANCHOR_FILES <- function() {
  list.files(here::here("src/config/_anchors"),
             pattern = "\\.yml$", full.names = TRUE)
}

`%||%` <- function(a, b) if (!is.null(a)) a else b


# ---------------------------------------------------------------------------
# CLI parsing
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, quick = FALSE, verbose = FALSE, help = FALSE)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a %in% c("-h", "--help"))   { out$help    <- TRUE;       i <- i + 1L; next }
    if (a == "--survey")            { out$survey  <- argv[i + 1L]; i <- i + 2L; next }
    if (a == "--quick")             { out$quick   <- TRUE;       i <- i + 1L; next }
    if (a == "--verbose")           { out$verbose <- TRUE;       i <- i + 1L; next }
    stop(sprintf("unknown argument: %s (see --help)", a), call. = FALSE)
  }
  out
}

.print_help <- function() {
  cat(
    "Usage: Rscript src/r/audit/run_all.R [options]\n",
    "\n",
    "Options:\n",
    "  --survey NAME   Run only for this survey (one of: ",
        paste(.SUPPORTED_SURVEYS, collapse = ", "), ").\n",
    "                  Default: every survey with prerequisites present.\n",
    "  --quick         Skip the two slowest modules (G1 drift, F4 codebook).\n",
    "  --verbose       Echo each module's full stdout (default: one summary line).\n",
    "  -h, --help      Show this message.\n",
    "\n",
    "Writes audit/SUMMARY.md. Exit 0 = all clean; 1 = fails detected; 2 = prereqs missing.\n",
    sep = ""
  )
}


# ---------------------------------------------------------------------------
# Logging helpers — progress to stderr so stdout stays a clean
# summary stream when the user pipes through `tee` or similar.
# ---------------------------------------------------------------------------
.log <- function(...) {
  msg <- paste0(...)
  cat(msg, file = stderr())
  if (!endsWith(msg, "\n")) cat("\n", file = stderr())
}

.log_module <- function(survey, module, detail = "") {
  prefix <- if (is.null(survey) || !nzchar(survey)) "[run_all] " else sprintf("[%s] ", survey)
  .log(prefix, "running ", module, if (nzchar(detail)) sprintf(" (%s)", detail) else "", "...")
}


# ---------------------------------------------------------------------------
# Run an external Rscript and capture exit code + stdout. We use system2()
# rather than callr or processx (no extra dep). stdout/stderr are merged so
# the summary parser doesn't have to think about which stream a module wrote
# to.
# ---------------------------------------------------------------------------
.run_external <- function(script_relpath, args, verbose = FALSE) {
  script_abs <- here::here(script_relpath)
  out <- suppressWarnings(system2(
    "Rscript", c(script_abs, args),
    stdout = TRUE, stderr = TRUE
  ))
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  if (verbose) {
    cat(sprintf("--- %s %s (exit=%d) ---\n",
                basename(script_relpath), paste(args, collapse = " "), status),
        file = stderr())
    cat(out, sep = "\n", file = stderr())
    cat("\n", file = stderr())
  }
  list(status = as.integer(status), stdout = out)
}


# ---------------------------------------------------------------------------
# CSV status counting. Each audit module writes a CSV with a `status`
# column; this helper tallies it. Returns a named integer vector covering
# every status seen — caller maps status names to ok/warn/fail/skip.
# ---------------------------------------------------------------------------
.count_csv_statuses <- function(csv_path) {
  if (!file.exists(csv_path)) {
    return(c(missing_csv = 1L))
  }
  df <- tryCatch(
    utils::read.csv(csv_path, stringsAsFactors = FALSE,
                    na.strings = c("", "NA")),
    error = function(e) NULL
  )
  if (is.null(df) || !"status" %in% names(df) || nrow(df) == 0L) {
    return(c())
  }
  tab <- table(df$status, useNA = "no")
  setNames(as.integer(tab), names(tab))
}

# Safe accessor for named integer vectors: returns 0L when the name is
# absent. (`v[["foo"]]` on a missing name throws "subscript out of bounds".)
.count_get <- function(counts, name) {
  v <- counts[name]
  if (length(v) == 0L || is.null(v) || is.na(v[[1]])) return(0L)
  as.integer(v[[1]])
}


# ---------------------------------------------------------------------------
# Top-N fail rows from a CSV (variable, wave, message-equivalent columns).
# Different modules use different column names — we accept whatever's there.
# ---------------------------------------------------------------------------
.top_fail_rows <- function(csv_path, fail_statuses = c("fail", "error",
                                                       "sign_disagreement",
                                                       "drift", "missing"),
                            n = 3L) {
  if (!file.exists(csv_path)) return(data.frame())
  df <- tryCatch(
    utils::read.csv(csv_path, stringsAsFactors = FALSE,
                    na.strings = c("", "NA")),
    error = function(e) NULL
  )
  if (is.null(df) || !"status" %in% names(df)) return(data.frame())
  fails <- df[df$status %in% fail_statuses, , drop = FALSE]
  if (nrow(fails) == 0L) return(data.frame())
  head(fails, n)
}


# ---------------------------------------------------------------------------
# Module 1: Layer 1 schema + cross-reference validation.
#
# Iterates list_survey_specs(<survey>), parses each YAML, runs
# validate_spec_full(spec, all_specs_in_survey = ...). validate_spec_full
# stops on first failure per spec, so we wrap each call in tryCatch and
# tally pass/fail across specs.
# ---------------------------------------------------------------------------
.run_layer_1 <- function(survey, verbose = FALSE) {
  .log_module(survey, "L1 schema validation")
  specs <- tryCatch(list_survey_specs(survey), error = function(e) NULL)
  if (is.null(specs) || length(specs) == 0L) {
    return(list(module = "L1 schema", status = "skip",
                ok = 0L, fail = 0L, total = 0L,
                first_fails = character(0),
                summary = "no specs found"))
  }
  parsed <- lapply(specs, function(p) tryCatch(yaml::read_yaml(p),
                                               error = function(e) NULL))
  ok_count <- 0L
  fail_count <- 0L
  first_fails <- character(0)
  for (i in seq_along(specs)) {
    sp <- parsed[[i]]
    if (is.null(sp)) {
      fail_count <- fail_count + 1L
      if (length(first_fails) < 3L) {
        first_fails <- c(first_fails, sprintf("%s: YAML parse error",
                                              basename(specs[i])))
      }
      next
    }
    res <- tryCatch(
      validate_spec_full(sp, all_specs_in_survey = parsed[!sapply(parsed, is.null)]),
      error = function(e) e
    )
    if (inherits(res, "error")) {
      fail_count <- fail_count + 1L
      if (length(first_fails) < 3L) {
        first_fails <- c(first_fails, sprintf("%s: %s",
                                              basename(specs[i]),
                                              conditionMessage(res)))
      }
    } else {
      ok_count <- ok_count + 1L
    }
  }
  total <- ok_count + fail_count
  list(
    module = "L1 schema",
    status = if (fail_count == 0L) "ok" else "fail",
    ok = ok_count, fail = fail_count, total = total,
    first_fails = first_fails,
    summary = sprintf("%d/%d", ok_count, total)
  )
}


# ---------------------------------------------------------------------------
# Module 2: Layer 3 output invariants.
#
# Reads audit/reports/<survey>/03-invariants.csv if present (produced by
# the survey's 99_create_final_dataset.R). We do NOT regenerate it.
# Status mapping: error → fail, warn → warn, ok → ok, skip → skip.
# ---------------------------------------------------------------------------
.run_layer_3 <- function(survey, verbose = FALSE) {
  .log_module(survey, "L3 invariants (read existing)")
  csv_path <- here::here("audit/reports", survey, "03-invariants.csv")
  if (!file.exists(csv_path)) {
    return(list(module = "L3 invariants", status = "skip",
                ok = 0L, warn = 0L, fail = 0L, skip = 0L,
                first_fails = character(0),
                summary = "needs harmonization rerun"))
  }
  counts <- .count_csv_statuses(csv_path)
  ok    <- .count_get(counts, "ok")
  warn  <- .count_get(counts, "warn")
  err   <- .count_get(counts, "error")
  skip  <- .count_get(counts, "skip")
  fails <- .top_fail_rows(csv_path, fail_statuses = "error")
  first <- character(0)
  if (nrow(fails) > 0L) {
    first <- vapply(seq_len(nrow(fails)), function(i) {
      r <- fails[i, ]
      sprintf("%s/%s/%s: %s",
              r$var_id %||% "?", r$wave %||% "?", r$check %||% "?",
              r$message %||% "")
    }, character(1))
  }
  list(
    module = "L3 invariants",
    status = if (err > 0L) "fail" else "ok",
    ok = as.integer(ok), warn = as.integer(warn),
    fail = as.integer(err), skip = as.integer(skip),
    first_fails = first,
    summary = sprintf("err=%d warn=%d", err, warn)
  )
}


# ---------------------------------------------------------------------------
# Module 3: Layer 2 codebook reconciliation (F4).
# Skipped if no data/<survey>/codebook/*.parquet on disk.
# ---------------------------------------------------------------------------
.run_layer_2_codebook <- function(survey, verbose = FALSE) {
  cb_dir <- here::here("data", survey, "codebook")
  has_codebook <- dir.exists(cb_dir) &&
    length(list.files(cb_dir, pattern = "\\.parquet$")) > 0L
  if (!has_codebook) {
    return(list(module = "L2 codebook", status = "skip",
                summary = "no codebook extractor",
                first_fails = character(0),
                ok = 0L, fail = 0L, unreconciled = 0L))
  }
  .log_module(survey, "L2 codebook reconciliation (F4)")
  rr <- .run_external("src/r/audit/02_check_codebook.R",
                      c("--survey", survey), verbose = verbose)
  csv_path <- here::here("audit/reports", survey, "02-codebook-recon.csv")
  counts <- .count_csv_statuses(csv_path)
  ok           <- .count_get(counts, "ok")
  fail         <- .count_get(counts, "fail")
  unreconciled <- .count_get(counts, "unreconciled")
  first_fails <- character(0)
  fails_df <- .top_fail_rows(csv_path, fail_statuses = "fail")
  if (nrow(fails_df) > 0L) {
    first_fails <- vapply(seq_len(nrow(fails_df)), function(i) {
      r <- fails_df[i, ]
      sprintf("%s/%s/%s: %s",
              r$variable %||% "?", r$wave %||% "?", r$check %||% "?",
              substr(r$message %||% "", 1, 120))
    }, character(1))
  }
  list(
    module = "L2 codebook",
    status = if (rr$status == 0L) "ok" else "fail",
    exit = rr$status,
    ok = as.integer(ok), fail = as.integer(fail),
    unreconciled = as.integer(unreconciled),
    first_fails = first_fails,
    summary = sprintf("%d ok, %d fail, %d unrec.", ok, fail, unreconciled)
  )
}


# ---------------------------------------------------------------------------
# Module 4a: Layer 4 anchor diagnostic (D3).
#
# Run once per anchor file whose anchor variable exists in this survey's
# harmonized rds. Anchor diagnostic uses the survey's harmonized rds via
# its own loader (which ABS-only resolution is fine for); for non-ABS
# surveys without the anchor variable column, skip.
# ---------------------------------------------------------------------------
.run_layer_4_anchor <- function(survey, verbose = FALSE) {
  harm_path <- .HARMONIZED_PATH(survey)
  if (!file.exists(harm_path)) {
    return(list(module = "L4 anchors", status = "skip",
                summary = "no harmonized rds",
                first_fails = character(0),
                ok = 0L, fail = 0L, sign_disagreement = 0L,
                weak = 0L, unreconciled = 0L))
  }
  d <- tryCatch(readRDS(harm_path), error = function(e) NULL)
  if (is.null(d)) {
    return(list(module = "L4 anchors", status = "skip",
                summary = "harmonized rds unreadable",
                first_fails = character(0),
                ok = 0L, fail = 0L, sign_disagreement = 0L,
                weak = 0L, unreconciled = 0L))
  }
  cols <- names(d)
  rm(d); invisible(gc(verbose = FALSE))

  anchors <- .ANCHOR_FILES()
  applicable <- character(0)
  for (af in anchors) {
    spec <- tryCatch(yaml::read_yaml(af), error = function(e) NULL)
    if (is.null(spec)) next
    anchor_var <- spec$anchor$variable %||% NA_character_
    surveys_field <- spec$anchor$surveys %||% NULL  # may be NULL = all
    survey_ok <- is.null(surveys_field) ||
      (survey %in% as.character(surveys_field))
    if (!is.na(anchor_var) && anchor_var %in% cols && survey_ok) {
      applicable <- c(applicable, af)
    }
  }

  if (length(applicable) == 0L) {
    return(list(module = "L4 anchors", status = "skip",
                summary = "no applicable anchors (anchor var absent)",
                first_fails = character(0),
                ok = 0L, fail = 0L, sign_disagreement = 0L,
                weak = 0L, unreconciled = 0L))
  }

  # The anchor diagnostic overwrites audit/reports/<survey>/04-anchors.csv
  # on every invocation. To capture every anchor's results, we pre-rename
  # the file between invocations and merge counts at the end. Simpler: run
  # in sequence and aggregate counts from each per-construct CSV by reading
  # the freshly-written CSV after each run.
  total_ok <- 0L; total_fail <- 0L; total_sign <- 0L
  total_weak <- 0L; total_unrec <- 0L
  worst_status <- "ok"
  first_fails <- character(0)
  for (af in applicable) {
    construct <- sub("\\.yml$", "", basename(af))
    .log_module(survey, "L4 anchor diagnostic (D3)", construct)
    rr <- .run_external("src/r/audit/04_anchor_diagnostic.R",
                        c("--survey", survey, "--anchor", af),
                        verbose = verbose)
    csv_path <- here::here("audit/reports", survey, "04-anchors.csv")
    counts <- .count_csv_statuses(csv_path)
    total_ok    <- total_ok    + .count_get(counts, "ok")
    total_fail  <- total_fail  + .count_get(counts, "sign_disagreement")
    total_sign  <- total_sign  + .count_get(counts, "sign_disagreement")
    total_weak  <- total_weak  + .count_get(counts, "weak")
    total_unrec <- total_unrec + .count_get(counts, "unreconciled")
    fails_df <- .top_fail_rows(csv_path,
                               fail_statuses = "sign_disagreement")
    if (nrow(fails_df) > 0L) {
      worst_status <- "fail"
      lines <- vapply(seq_len(min(3L, nrow(fails_df))), function(i) {
        r <- fails_df[i, ]
        sprintf("%s/%s/%s: expected=%s observed=%s",
                construct, r$variable %||% "?", r$wave %||% "?",
                r$expected_sign %||% "?", r$observed_sign %||% "?")
      }, character(1))
      # Keep only first 3 across all constructs.
      slots <- 3L - length(first_fails)
      if (slots > 0L) {
        first_fails <- c(first_fails, head(lines, slots))
      }
    }
  }
  list(
    module = "L4 anchors",
    status = worst_status,
    ok = total_ok, fail = total_fail,
    sign_disagreement = total_sign, weak = total_weak,
    unreconciled = total_unrec,
    first_fails = first_fails,
    summary = sprintf("%d constructs, %d sign-disagreements, %d weak",
                      length(applicable), total_sign, total_weak)
  )
}


# ---------------------------------------------------------------------------
# Module 4b: Layer 4 strict reversal (D4). Module is ABS-only in v1; for
# other surveys it writes a CSV of all `skip` rows. We surface the skip
# semantics rather than calling it a fail.
# ---------------------------------------------------------------------------
.run_layer_4_strict <- function(survey, verbose = FALSE) {
  .log_module(survey, "L4 strict reversal (D4)")
  rr <- .run_external("src/r/audit/04_strict_reversal.R",
                      c("--survey", survey), verbose = verbose)
  csv_path <- here::here("audit/reports", survey, "04-strict-reversal.csv")
  counts <- .count_csv_statuses(csv_path)
  ok   <- .count_get(counts, "ok")
  fail <- .count_get(counts, "fail")
  skip <- .count_get(counts, "skip")
  status <- if (rr$status == 0L && fail == 0L) {
    if (ok == 0L && skip > 0L) "skip" else "ok"
  } else "fail"
  first_fails <- character(0)
  fails_df <- .top_fail_rows(csv_path, fail_statuses = "fail")
  if (nrow(fails_df) > 0L) {
    first_fails <- vapply(seq_len(nrow(fails_df)), function(i) {
      r <- fails_df[i, ]
      sprintf("%s/%s/%s: %s",
              r$variable %||% "?", r$wave %||% "?", r$fn %||% "?",
              substr(r$message %||% "", 1, 100))
    }, character(1))
  }
  list(
    module = "L4 strict",
    status = status,
    exit = rr$status,
    ok = as.integer(ok), fail = as.integer(fail), skip = as.integer(skip),
    first_fails = first_fails,
    summary = sprintf("%d ok, %d fail, %d skip", ok, fail, skip)
  )
}


# ---------------------------------------------------------------------------
# Module 5: Layer 5 cross-wave drift (G1). One of the slowest modules —
# skipped under --quick.
#
# Drift has no fail concept (the brief documents Layer 5 as soft-only).
# We surface the row count of the kept output so the user can see whether
# anything was actually computed; status is always "ok" unless the module
# crashes.
# ---------------------------------------------------------------------------
.run_layer_5_drift <- function(survey, verbose = FALSE, skip = FALSE) {
  if (skip) {
    return(list(module = "L5 drift", status = "skip",
                summary = "--quick", first_fails = character(0),
                kept = 0L))
  }
  .log_module(survey, "L5 cross-wave drift (G1)")
  rr <- .run_external("src/r/audit/05_drift_check.R",
                      c("--survey", survey), verbose = verbose)
  csv_path <- here::here("audit/reports", survey, "05-drift.csv")
  kept <- 0L
  if (file.exists(csv_path)) {
    df <- tryCatch(utils::read.csv(csv_path, stringsAsFactors = FALSE),
                   error = function(e) NULL)
    if (!is.null(df)) kept <- nrow(df)
  }
  status <- if (rr$status == 0L) "ok" else "fail"
  list(
    module = "L5 drift",
    status = status,
    exit = rr$status,
    kept = kept,
    first_fails = character(0),
    summary = sprintf("%d kept rows", kept)
  )
}


# ---------------------------------------------------------------------------
# Module 6a: Layer 6 determinism (C4). Requires outputs/<survey>/manifest.json.
# ---------------------------------------------------------------------------
.run_layer_6_determinism <- function(survey, verbose = FALSE) {
  manifest <- here::here("outputs", survey, "manifest.json")
  if (!file.exists(manifest)) {
    return(list(module = "L6 determinism", status = "skip",
                summary = "no manifest", first_fails = character(0)))
  }
  .log_module(survey, "L6 determinism (C4)")
  rr <- .run_external("src/r/audit/06_check_determinism.R",
                      c("--survey", survey), verbose = verbose)
  status <- if (rr$status == 0L) "ok" else "fail"
  # Extract problem lines from stdout.
  first_fails <- character(0)
  if (status == "fail") {
    lines <- rr$stdout
    drift_lines <- grep("^\\s*\\[(drift|missing)\\]", lines, value = TRUE)
    first_fails <- head(trimws(drift_lines), 3L)
  }
  list(
    module = "L6 determinism",
    status = status, exit = rr$status,
    first_fails = first_fails,
    summary = if (status == "ok") "all paths match" else sprintf("exit=%d", rr$status)
  )
}


# ---------------------------------------------------------------------------
# Module 6b: Layer 6 input drift (C5). Requires the same manifest.
# ---------------------------------------------------------------------------
.run_layer_6_input_drift <- function(survey, verbose = FALSE) {
  manifest <- here::here("outputs", survey, "manifest.json")
  if (!file.exists(manifest)) {
    return(list(module = "L6 input drift", status = "skip",
                summary = "no manifest", first_fails = character(0)))
  }
  .log_module(survey, "L6 input drift (C5)")
  rr <- .run_external("src/r/audit/06_check_input_drift.R",
                      c("--survey", survey), verbose = verbose)
  status <- if (rr$status == 0L) "ok" else "fail"
  first_fails <- character(0)
  if (status == "fail") {
    lines <- rr$stdout
    changed_idx <- grep("^CHANGED:", lines)
    if (length(changed_idx) > 0L) {
      # Take next non-empty path lines, up to 3.
      tail_lines <- head(grep("^  [^ ]", lines, value = TRUE), 3L)
      first_fails <- trimws(tail_lines)
    }
  }
  list(
    module = "L6 input drift",
    status = status, exit = rr$status,
    first_fails = first_fails,
    summary = if (status == "ok") "all inputs unchanged" else "raw inputs changed"
  )
}


# ---------------------------------------------------------------------------
# Cross-cutting: recoding registry (A4 helper). Run once.
# ---------------------------------------------------------------------------
.run_registry_check <- function(verbose = FALSE) {
  .log_module(NULL, "recoding registry drift")
  rr <- .run_external("src/r/audit/check_registry_complete.R",
                      character(0), verbose = verbose)
  status <- if (rr$status == 0L) "ok" else "fail"
  first_lines <- character(0)
  if (status == "fail") {
    first_lines <- head(grep("^\\s*-\\s+", rr$stdout, value = TRUE), 3L)
  }
  list(
    module = "Recoding registry",
    status = status, exit = rr$status,
    first_fails = first_lines,
    summary = if (status == "ok") "OK" else "DRIFT"
  )
}


# ---------------------------------------------------------------------------
# Per-survey orchestrator. Returns a list of module results for one survey.
# ---------------------------------------------------------------------------
.run_one_survey <- function(survey, quick = FALSE, verbose = FALSE) {
  results <- list()
  results$L1 <- .run_layer_1(survey, verbose)
  results$L3 <- .run_layer_3(survey, verbose)
  results$L2_codebook <- if (quick) {
    list(module = "L2 codebook", status = "skip", summary = "--quick",
         first_fails = character(0), ok = 0L, fail = 0L, unreconciled = 0L)
  } else {
    .run_layer_2_codebook(survey, verbose)
  }
  results$L4_anchor <- .run_layer_4_anchor(survey, verbose)
  results$L4_strict <- .run_layer_4_strict(survey, verbose)
  results$L5_drift  <- .run_layer_5_drift(survey, verbose, skip = quick)
  results$L6_determ <- .run_layer_6_determinism(survey, verbose)
  results$L6_input  <- .run_layer_6_input_drift(survey, verbose)
  results
}


# ---------------------------------------------------------------------------
# Status icon for the table.
# ---------------------------------------------------------------------------
.status_icon <- function(status) {
  switch(
    status,
    ok = "OK",
    fail = "FAIL",
    skip = "skip",
    warn = "warn",
    "?"
  )
}

# Compact cell: icon + count summary.
.cell <- function(res) {
  ic <- .status_icon(res$status %||% "?")
  s <- res$summary %||% ""
  if (!nzchar(s)) ic else sprintf("%s %s", ic, s)
}


# ---------------------------------------------------------------------------
# Markdown summary writer.
# ---------------------------------------------------------------------------
.write_summary <- function(all_results, registry_result, args, runtime_sec,
                            git_info, jeff_open, surveys_attempted,
                            surveys_with_data, skipped_modules) {

  out_path <- here::here("audit", "SUMMARY.md")
  con <- file(out_path, open = "w")
  on.exit(close(con), add = TRUE)
  w <- function(...) cat(..., "\n", sep = "", file = con)

  ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")

  w("# Audit summary — ", ts)
  w("")
  w("git_commit: `", git_info$commit, "`  git_dirty: ",
    if (git_info$dirty) "**true**" else "false")
  w("")
  w("Mode: ", if (args$quick) "`--quick` (G1, F4 skipped)" else "full",
    if (!is.null(args$survey)) sprintf(" — single survey `%s`", args$survey) else "")
  w("Runtime: ", sprintf("%.1f s", runtime_sec))
  w("")

  # ---- Per-survey table -------------------------------------------------
  w("## Per-survey status")
  w("")
  w("| Survey | L1 schema | L3 invariants | L2 codebook | L4 anchors | L4 strict | L5 drift | L6 determ | L6 input |")
  w("|--------|-----------|---------------|-------------|------------|-----------|----------|-----------|----------|")
  for (s in surveys_attempted) {
    r <- all_results[[s]]
    if (is.null(r)) next
    w(sprintf("| %s | %s | %s | %s | %s | %s | %s | %s | %s |",
              s,
              .cell(r$L1),
              .cell(r$L3),
              .cell(r$L2_codebook),
              .cell(r$L4_anchor),
              .cell(r$L4_strict),
              .cell(r$L5_drift),
              .cell(r$L6_determ),
              .cell(r$L6_input)))
  }
  w("")

  # ---- Top fail findings ------------------------------------------------
  w("## Top audit findings")
  w("")
  fail_rows <- list()
  for (s in surveys_attempted) {
    r <- all_results[[s]]
    if (is.null(r)) next
    for (mod_name in names(r)) {
      m <- r[[mod_name]]
      if (is.null(m$first_fails) || length(m$first_fails) == 0L) next
      fail_count <- m$fail %||% 0L
      for (line in m$first_fails) {
        fail_rows[[length(fail_rows) + 1L]] <- list(
          survey = s, module = m$module,
          fail_count = as.integer(fail_count),
          line = line
        )
      }
    }
  }
  if (length(fail_rows) == 0L) {
    w("_No fail rows surfaced._")
  } else {
    # Sort by fail_count desc, then survey, then module.
    ord <- order(
      -vapply(fail_rows, function(x) x$fail_count, integer(1)),
      vapply(fail_rows, function(x) x$survey, character(1)),
      vapply(fail_rows, function(x) x$module, character(1))
    )
    fail_rows <- fail_rows[ord]
    n_show <- min(10L, length(fail_rows))
    for (i in seq_len(n_show)) {
      fr <- fail_rows[[i]]
      csv_link <- sprintf("`audit/reports/%s/`", fr$survey)
      w(sprintf("%d. **[%s]** %s — %s  \n   See %s",
                i, fr$survey, fr$module, fr$line, csv_link))
    }
  }
  w("")

  # ---- Cross-cutting ----------------------------------------------------
  w("## Cross-cutting")
  w("")
  w("- Recoding registry: ", registry_result$summary,
    if (registry_result$status == "fail") "" else "")
  if (length(registry_result$first_fails) > 0L) {
    for (line in registry_result$first_fails) w("    - `", line, "`")
  }
  w("- JEFF_MUST_INVESTIGATE.md: ", jeff_open, " open finding",
    if (jeff_open == 1L) "" else "s",
    " (high+medium priority)")
  w("")

  # ---- Skipped modules --------------------------------------------------
  w("## Skipped modules (prerequisites missing)")
  w("")
  if (length(skipped_modules) == 0L) {
    w("_None._")
  } else {
    for (line in skipped_modules) w("- ", line)
  }
  w("")

  w("---")
  w("Generated by `src/r/audit/run_all.R` at ", ts, ".")

  invisible(out_path)
}


# ---------------------------------------------------------------------------
# Git info — best-effort. Returns commit + dirty.
# ---------------------------------------------------------------------------
.git_info <- function() {
  commit <- tryCatch(
    suppressWarnings(system2("git", c("rev-parse", "--short", "HEAD"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) "unknown"
  )
  if (length(commit) == 0L || !nzchar(commit[1])) commit <- "unknown"
  status <- tryCatch(
    suppressWarnings(system2("git", c("status", "--porcelain"),
                             stdout = TRUE, stderr = FALSE)),
    error = function(e) character(0)
  )
  list(commit = commit[1], dirty = length(status) > 0L)
}


# ---------------------------------------------------------------------------
# Count "open" findings in JEFF_MUST_INVESTIGATE.md. Definition for v1:
# every `### ` heading between `## 🔴 High priority` (inclusive of subsequent
# items) and `## 📋 Residual systematic findings` (or `## ✅ Resolved findings`,
# whichever comes first). The brief allows simplistic counting; we don't
# parse status per-finding.
# ---------------------------------------------------------------------------
.count_jeff_open <- function() {
  path <- here::here("JEFF_MUST_INVESTIGATE.md")
  if (!file.exists(path)) return(NA_integer_)
  lines <- readLines(path, warn = FALSE)
  start_idx <- grep("^##\\s+\U0001F534", lines)  # red circle emoji
  if (length(start_idx) == 0L) return(0L)
  end_idx <- grep("^##\\s+(\U0001F4CB|\U00002705)", lines)  # clipboard or check mark
  end_idx <- end_idx[end_idx > start_idx[1]]
  end <- if (length(end_idx) > 0L) end_idx[1] else length(lines)
  region <- lines[start_idx[1]:(end - 1L)]
  sum(grepl("^###\\s", region))
}


# ---------------------------------------------------------------------------
# Aggregate skipped-module summary across surveys (for the bottom table).
# ---------------------------------------------------------------------------
.aggregate_skipped <- function(all_results) {
  out <- character(0)
  for (s in names(all_results)) {
    r <- all_results[[s]]
    if (is.null(r)) next
    skipped <- character(0)
    for (mod_name in names(r)) {
      m <- r[[mod_name]]
      if (identical(m$status, "skip") && !identical(m$summary, "--quick")) {
        skipped <- c(skipped, sprintf("%s (%s)", m$module, m$summary))
      }
    }
    if (length(skipped) > 0L) {
      out <- c(out, sprintf("**%s**: %s", s, paste(skipped, collapse = "; ")))
    }
  }
  out
}


# ---------------------------------------------------------------------------
# Tldr to stdout.
# ---------------------------------------------------------------------------
.print_tldr <- function(all_results, surveys_attempted, surveys_with_data,
                         jeff_open, summary_path, exit_code) {
  total_fail <- 0L
  per_survey_fail <- integer(0)
  for (s in surveys_attempted) {
    r <- all_results[[s]]
    if (is.null(r)) next
    sf <- 0L
    for (mod_name in names(r)) {
      m <- r[[mod_name]]
      sf <- sf + as.integer(m$fail %||% 0L)
    }
    per_survey_fail <- c(per_survey_fail, setNames(sf, s))
    total_fail <- total_fail + sf
  }
  per_survey_fail <- per_survey_fail[order(-per_survey_fail)]
  top3 <- head(per_survey_fail[per_survey_fail > 0L], 5L)
  top_str <- if (length(top3) == 0L) "" else
    paste(paste(toupper(names(top3)), top3, sep = " "), collapse = ", ")

  cat("=== AUDIT SUMMARY ===\n")
  cat(sprintf("%d surveys checked, %d with full prerequisites\n",
              length(surveys_attempted), length(surveys_with_data)))
  cat(sprintf("Total fails: %d%s\n", total_fail,
              if (nzchar(top_str)) sprintf(" (%s)", top_str) else ""))
  cat(sprintf("%d open finding%s in JEFF_MUST_INVESTIGATE.md\n",
              jeff_open, if (jeff_open == 1L) "" else "s"))
  cat(sprintf("Full report: %s\n",
              sub(here::here(), "", summary_path, fixed = TRUE) |>
                sub("^/", "", x = _)))
  cat(sprintf("Exit: %d %s\n", exit_code,
              if (exit_code == 0L) "(clean)"
              else if (exit_code == 1L) "(fails detected)"
              else "(prereqs missing)"))
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
.main <- function(argv) {
  args <- .parse_cli_args(argv)
  if (args$help) { .print_help(); quit(status = 0) }

  if (!is.null(args$survey)) {
    if (!(args$survey %in% .SUPPORTED_SURVEYS)) {
      stop(sprintf(
        "unknown survey '%s'. Supported: %s",
        args$survey, paste(.SUPPORTED_SURVEYS, collapse = ", ")
      ), call. = FALSE)
    }
    target_surveys <- args$survey
  } else {
    target_surveys <- .SUPPORTED_SURVEYS
  }

  start_time <- Sys.time()

  # Filter by prerequisite existence: a survey is included if it has either
  # a harmonized rds, a YAML spec dir, or both. (We skip a survey entirely
  # when neither is present — that means it isn't onboarded yet.)
  surveys_attempted <- character(0)
  surveys_with_data <- character(0)
  for (s in target_surveys) {
    has_specs <- tryCatch(length(list_survey_specs(s)) > 0L,
                          error = function(e) FALSE)
    has_data <- file.exists(.HARMONIZED_PATH(s))
    if (has_specs || has_data) {
      surveys_attempted <- c(surveys_attempted, s)
      if (has_data) surveys_with_data <- c(surveys_with_data, s)
    }
  }

  if (length(surveys_attempted) == 0L) {
    .log("[run_all] no surveys with prerequisites; nothing to do")
    quit(status = 2)
  }

  all_results <- list()
  for (s in surveys_attempted) {
    .log("\n[run_all] === survey: ", s, " ===")
    all_results[[s]] <- .run_one_survey(s, quick = args$quick,
                                        verbose = args$verbose)
  }

  registry_result <- .run_registry_check(verbose = args$verbose)
  jeff_open <- .count_jeff_open()
  git_info <- .git_info()
  runtime_sec <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  skipped_modules <- .aggregate_skipped(all_results)

  # Determine exit code.
  any_fail <- FALSE
  for (s in surveys_attempted) {
    r <- all_results[[s]]
    for (mod_name in names(r)) {
      m <- r[[mod_name]]
      if (identical(m$status, "fail")) any_fail <- TRUE
    }
  }
  if (identical(registry_result$status, "fail")) any_fail <- TRUE

  prereq_missing <- length(surveys_with_data) < length(surveys_attempted)

  exit_code <- if (any_fail) 1L
               else if (prereq_missing && length(surveys_with_data) == 0L) 2L
               else 0L

  summary_path <- .write_summary(
    all_results = all_results,
    registry_result = registry_result,
    args = args,
    runtime_sec = runtime_sec,
    git_info = git_info,
    jeff_open = jeff_open %||% 0L,
    surveys_attempted = surveys_attempted,
    surveys_with_data = surveys_with_data,
    skipped_modules = skipped_modules
  )

  .print_tldr(
    all_results, surveys_attempted, surveys_with_data,
    jeff_open %||% 0L, summary_path, exit_code
  )

  quit(status = exit_code)
}


if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  .main(argv)
}
