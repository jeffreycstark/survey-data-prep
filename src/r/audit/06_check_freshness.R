#!/usr/bin/env Rscript
# src/r/audit/06_check_freshness.R
#
# Layer 6 — Pre-flight freshness gate.
#
# Answers one question: "if I re-ran this survey's pipeline right now, would
# the harmonized output change?" Run it BEFORE consuming data/processed/*.rds
# in a paper, not after a build.
#
# WHY THIS EXISTS ALONGSIDE 06_check_determinism.R
#
# `06_check_determinism.R --fast` re-hashes the same manifest and reports
# per-path drift, and it is wired into run_all.R. It is a fine detector. But:
#
#   1. It only re-hashes paths ALREADY RECORDED in the manifest. A YAML spec
#      added since the last harmonization run is invisible to it — zero drift,
#      exit 0 — even though the harmonized output is missing every variable
#      that spec declares. This script diffs the manifest's spec list against
#      `list_survey_specs(survey)` and reports specs as added/missing.
#   2. It has no --all sweep, so "is any of my processed data stale?" takes
#      ten invocations and ten separate reads.
#   3. It reports drift flatly. Drift in specs/inputs/engine means REBUILD;
#      drift in outputs means somebody wrote to a harmonized file out of band,
#      which is a different problem with a different fix. This script separates
#      the two verdicts and prints the exact remediation command.
#
# The manifest is written at the END of 99_create_final_dataset.R, so a check
# run immediately after a build always passes. The failure this catches is a
# spec or engine file committed WITHOUT a re-run — the gitignored .rds then
# serves stale values indefinitely, with nothing to signal it. That is how
# `corr_punishment_*` sat NA-where-7 in KIPA for 2018-2020 (fixed 2026-07-09).
#
# Hashing is delegated to `.hash_file()` in src/r/utils/provenance.R — the same
# function `write_manifest()` uses to record the hashes we compare against, so
# there is exactly one hashing implementation in the repo.
#
# Usage:
#   Rscript src/r/audit/06_check_freshness.R --survey kipa-corruption
#   Rscript src/r/audit/06_check_freshness.R --all
#   Rscript src/r/audit/06_check_freshness.R --all --quiet
#   Rscript src/r/audit/06_check_freshness.R --help
#
# Exit codes:
#   0 — every checked survey is FRESH (or was skipped for want of a manifest)
#   1 — at least one survey is STALE or TAMPERED, or the invocation was invalid

suppressPackageStartupMessages({
  for (pkg in c("jsonlite", "digest", "here")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required (renv::install('%s'))", pkg, pkg),
           call. = FALSE)
    }
  }
})

`%||%` <- function(a, b) if (is.null(a)) b else a

# Reuse the repo's single hashing implementation + spec discovery.
source(here::here("src", "r", "utils", "provenance.R"))
source(here::here("src", "r", "utils", "spec_discovery.R"))

# MUST be a SUPERSET of run_all.R's .SUPPORTED_SURVEYS — enforced by
# src/r/audit/07_module_coverage.R, not by hand.
#
# Freshness legitimately covers MORE than the survey checks do. Staleness is the
# one failure every generated artifact is exposed to, including the non-survey
# macro panels that have no YAML specs and therefore cannot be label-reconciled,
# battery-checked or gated. Those modules appear here but NOT in
# .SUPPORTED_SURVEYS, and are registered in
# src/config/_audit/module_coverage_exemptions.yml.
.FRESHNESS_SURVEYS <- c(
  # YAML-spec surveys (mirror .SUPPORTED_SURVEYS)
  "abs", "wvs", "lbs", "afro", "arab-barometer",
  "kamos", "kgss", "kipa-corruption", "kinu", "ipus", "gcb", "klosa",
  # Non-survey modules: freshness-only (see exemptions YAML)
  "vdem", "marpor", "unga", "unsc", "oecd_dac"
)

# Surveys whose pipeline lives directly in src/r/data_prep_modules/ rather
# than a per-survey subdirectory.
.FRESHNESS_NO_SUBDIR <- "abs"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
.print_usage <- function() {
  cat(
    "Usage: Rscript src/r/audit/06_check_freshness.R (--survey <name> | --all) [--quiet]\n",
    "\n",
    "Reports, per survey, whether re-running the pipeline would change the\n",
    "harmonized output. Run BEFORE consuming data/processed/*.rds.\n",
    "\n",
    "Verdicts:\n",
    "  FRESH     manifest matches every spec, input, engine file and output\n",
    "  STALE     a spec/input/engine file changed, or a spec was added or\n",
    "            deleted, since the last run -> re-run the pipeline\n",
    "  TAMPERED  a harmonized output no longer matches its recorded hash\n",
    "            -> the file was written outside the pipeline; investigate\n",
    "  SKIP      no manifest (survey never harmonized here)\n",
    "\n",
    "A survey can be both STALE and TAMPERED; STALE is reported first.\n",
    "\n",
    "Arguments:\n",
    "  --survey <name>   One survey (e.g. abs, kgss, kipa-corruption).\n",
    "  --all             Every supported survey.\n",
    "  --quiet           Only print non-FRESH surveys and the summary.\n",
    "  -h, --help        Print this help and exit 0.\n",
    "\n",
    "Exit codes:\n",
    "  0   all checked surveys FRESH (or SKIPped)\n",
    "  1   any survey STALE or TAMPERED, or invalid invocation\n",
    sep = ""
  )
}

.parse_args <- function(args) {
  out <- list(help = FALSE, survey = NULL, all = FALSE, quiet = FALSE,
              error = NULL)
  if (length(args) == 0L) {
    out$error <- "no arguments provided; pass --survey <name> or --all"
    return(out)
  }
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a %in% c("-h", "--help")) { out$help <- TRUE; return(out) }
    if (a == "--all")   { out$all   <- TRUE; i <- i + 1L; next }
    if (a == "--quiet") { out$quiet <- TRUE; i <- i + 1L; next }
    if (a == "--survey") {
      if (i == length(args)) {
        out$error <- "--survey requires a value"; return(out)
      }
      out$survey <- args[[i + 1L]]; i <- i + 2L; next
    }
    out$error <- sprintf("unrecognized argument: %s", a)
    return(out)
  }
  if (out$all && !is.null(out$survey)) {
    out$error <- "pass --survey or --all, not both"
    return(out)
  }
  if (!out$all && is.null(out$survey)) {
    out$error <- "--survey <name> or --all is required"
    return(out)
  }
  if (!is.null(out$survey) && !(out$survey %in% .FRESHNESS_SURVEYS)) {
    out$error <- sprintf("unknown survey '%s' (expected one of: %s)",
                         out$survey, paste(.FRESHNESS_SURVEYS, collapse = ", "))
  }
  out
}


# ---------------------------------------------------------------------------
# Hash a path via provenance.R's .hash_file(). Returns NA_character_ when the
# file is missing or unreadable, so callers can branch on is.na().
# ---------------------------------------------------------------------------
.freshness_sha <- function(path) {
  h <- .hash_file(path)
  if (!is.null(h$error) || is.null(h$sha256)) return(NA_character_)
  h$sha256
}


# ---------------------------------------------------------------------------
# Normalize a manifest path for set comparison. Manifests written on this
# machine store absolute paths for specs; engine_versions stores repo-relative.
# ---------------------------------------------------------------------------
.norm_path <- function(p) {
  if (length(p) == 0L) return(character())
  normalizePath(p, winslash = "/", mustWork = FALSE)
}


# ---------------------------------------------------------------------------
# Compare one recorded array (inputs[] / specs[] / outputs[]) against disk.
# Returns list(drift = <chr paths>, missing = <chr paths>, ok = <int>).
# ---------------------------------------------------------------------------
.check_recorded <- function(entries) {
  drift <- character(); missing <- character(); ok <- 0L
  for (e in entries %||% list()) {
    path <- e$path %||% NA_character_
    old  <- e$sha256 %||% NA_character_
    if (is.na(path) || !nzchar(path)) {
      missing <- c(missing, "<malformed manifest entry>")
      next
    }
    if (!file.exists(path)) { missing <- c(missing, path); next }
    new <- .freshness_sha(path)
    if (is.na(new))            { missing <- c(missing, path); next }
    # A recorded entry with no hash is not reassurance — treat as drift.
    if (is.na(old) || !nzchar(old)) { drift <- c(drift, path); next }
    if (identical(new, old)) ok <- ok + 1L else drift <- c(drift, path)
  }
  list(drift = drift, missing = missing, ok = ok)
}


# ---------------------------------------------------------------------------
# Specs the manifest never saw. This is the case 06_check_determinism.R misses:
# a new YAML added to src/config/<survey>/harmonize/ but never harmonized.
#
# Returns character() when the spec directory cannot be resolved (e.g. a
# scaffold survey), rather than erroring — absence of a spec dir is not drift.
# ---------------------------------------------------------------------------
.added_specs <- function(survey, recorded_paths) {
  on_disk <- tryCatch(list_survey_specs(survey), error = function(e) character())
  if (length(on_disk) == 0L) return(character())
  setdiff(.norm_path(on_disk), .norm_path(recorded_paths))
}


# ---------------------------------------------------------------------------
# engine_versions is a named map {relative_path: sha256}, not an array.
# ---------------------------------------------------------------------------
.check_engine <- function(engine_map) {
  drift <- character(); missing <- character(); ok <- 0L
  for (rel in names(engine_map %||% list())) {
    old <- engine_map[[rel]]
    abs <- here::here(rel)
    if (!file.exists(abs)) { missing <- c(missing, rel); next }
    new <- .freshness_sha(abs)
    if (is.na(new)) { missing <- c(missing, rel); next }
    if (is.null(old) || is.na(old) || !nzchar(old)) { drift <- c(drift, rel); next }
    if (identical(new, old)) ok <- ok + 1L else drift <- c(drift, rel)
  }
  list(drift = drift, missing = missing, ok = ok)
}


# ---------------------------------------------------------------------------
# The command that refreshes a survey.
# ---------------------------------------------------------------------------
.rebuild_cmd <- function(survey) {
  dir <- if (survey %in% .FRESHNESS_NO_SUBDIR) {
    "src/r/data_prep_modules"
  } else {
    file.path("src/r/data_prep_modules", survey)
  }
  # Non-survey modules (vdem, marpor, unga, unsc, oecd_dac) have NO
  # 2_harmonize_all.R — there are no questionnaire items to harmonize, so the
  # pipeline is a single 99_create_final_dataset.R. Emitting the survey-shaped
  # two-step command for them prints a fix that cannot run.
  harmonize <- file.path(dir, "2_harmonize_all.R")
  if (!file.exists(here::here(harmonize))) {
    return(sprintf("Rscript %s/99_create_final_dataset.R", dir))
  }
  sprintf("Rscript %s/2_harmonize_all.R && Rscript %s/99_create_final_dataset.R",
          dir, dir)
}


# ---------------------------------------------------------------------------
# Check one survey. Returns a list with verdict + reason detail.
# Exposed (not dot-prefixed) so tests can call it directly.
# ---------------------------------------------------------------------------
check_survey_freshness <- function(survey, manifest_path = NULL) {
  if (is.null(manifest_path)) {
    manifest_path <- here::here("outputs", survey, "manifest.json")
  }
  if (!file.exists(manifest_path)) {
    return(list(survey = survey, verdict = "SKIP",
                reason = "no manifest.json (survey never harmonized here)",
                rebuild = character(), tamper = character()))
  }

  manifest <- tryCatch(
    jsonlite::read_json(manifest_path, simplifyVector = FALSE),
    error = function(e) e
  )
  if (inherits(manifest, "error")) {
    return(list(survey = survey, verdict = "STALE",
                reason = sprintf("unreadable manifest: %s",
                                 conditionMessage(manifest)),
                rebuild = manifest_path, tamper = character()))
  }

  specs_res  <- .check_recorded(manifest$specs)
  inputs_res <- .check_recorded(manifest$inputs)
  out_res    <- .check_recorded(manifest$outputs)
  eng_res    <- .check_engine(manifest$engine_versions)

  recorded_spec_paths <- vapply(
    manifest$specs %||% list(),
    function(e) e$path %||% NA_character_,
    character(1)
  )
  added <- .added_specs(survey, recorded_spec_paths[!is.na(recorded_spec_paths)])

  # sprintf() over character(0) yields character(0), so an absent trigger
  # contributes nothing and no explicit emptiness guard is needed.
  #
  # Rebuild triggers: anything that feeds the harmonization.
  rebuild <- c(
    sprintf("spec drift: %s",   specs_res$drift),
    sprintf("spec missing: %s", specs_res$missing),
    sprintf("spec ADDED (never harmonized): %s", added),
    sprintf("input drift: %s",   inputs_res$drift),
    sprintf("input missing: %s", inputs_res$missing),
    sprintf("engine drift: %s",   eng_res$drift),
    sprintf("engine missing: %s", eng_res$missing)
  )

  # Tamper triggers: the output itself no longer matches what was written.
  tamper <- c(
    sprintf("output drift: %s",   out_res$drift),
    sprintf("output missing: %s", out_res$missing)
  )

  verdict <- if (length(rebuild) > 0L) "STALE"
             else if (length(tamper) > 0L) "TAMPERED"
             else "FRESH"

  list(survey = survey, verdict = verdict, reason = NULL,
       rebuild = rebuild, tamper = tamper,
       counts = list(specs_ok = specs_res$ok, inputs_ok = inputs_res$ok,
                     outputs_ok = out_res$ok, engine_ok = eng_res$ok))
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main <- function() {
  parsed <- .parse_args(commandArgs(trailingOnly = TRUE))
  if (parsed$help) { .print_usage(); quit(status = 0) }
  if (!is.null(parsed$error)) {
    cat("ERROR:", parsed$error, "\n\n")
    .print_usage()
    quit(status = 1)
  }

  surveys <- if (parsed$all) .FRESHNESS_SURVEYS else parsed$survey
  results <- lapply(surveys, check_survey_freshness)

  cat("[freshness] would a re-run change the harmonized output?\n\n")
  for (r in results) {
    if (parsed$quiet && r$verdict == "FRESH") next
    cat(sprintf("  %-9s %s\n", r$verdict, r$survey))
    if (!is.null(r$reason)) cat(sprintf("      %s\n", r$reason))
    for (m in r$rebuild) cat(sprintf("      %s\n", m))
    for (m in r$tamper)  cat(sprintf("      %s\n", m))
    if (r$verdict == "STALE") {
      cat(sprintf("      fix: %s\n", .rebuild_cmd(r$survey)))
    }
    if (r$verdict == "TAMPERED") {
      cat("      fix: a harmonized file changed outside the pipeline.\n")
      cat("           Re-run to regenerate, then diff before trusting it.\n")
    }
  }

  verdicts <- vapply(results, function(r) r$verdict, character(1))
  n_stale  <- sum(verdicts == "STALE")
  n_tamper <- sum(verdicts == "TAMPERED")
  n_fresh  <- sum(verdicts == "FRESH")
  n_skip   <- sum(verdicts == "SKIP")

  cat(sprintf("\n  fresh=%d stale=%d tampered=%d skipped=%d (of %d)\n",
              n_fresh, n_stale, n_tamper, n_skip, length(results)))

  if (n_stale > 0L || n_tamper > 0L) quit(status = 1)
  quit(status = 0)
}

# Tests source this file to call check_survey_freshness() directly. They set
# FRESHNESS_SOURCE_ONLY=1 to suppress main(); every other invocation (including
# a bare `Rscript 06_check_freshness.R` with no args, which must print usage and
# exit 1) runs it.
if (!nzchar(Sys.getenv("FRESHNESS_SOURCE_ONLY"))) {
  main()
}
