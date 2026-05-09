#!/usr/bin/env Rscript
# src/r/audit/check_registry_complete.R
#
# Audit helper: verify that src/r/utils/recoding_registry.yml is in sync with
# the functions actually defined in src/r/utils/recoding.R.
#
# Reports drift in BOTH directions:
#   1. Registry entries with no corresponding loaded function (stale/typo'd entry)
#   2. Loaded functions with no registry entry (missing catalogue row)
#
# Exit codes:
#   0 — registry complete (prints "OK")
#   1 — drift detected (prints structured drift list, non-zero exit)
#
# Usage:
#   Rscript src/r/audit/check_registry_complete.R

suppressPackageStartupMessages({
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required (renv::install('yaml'))")
  }
})

# Resolve repo root (script may be invoked from anywhere)
script_path <- tryCatch(
  normalizePath(sys.frames()[[1]]$ofile %||% commandArgs(trailingOnly = FALSE)[
    grep("--file=", commandArgs(trailingOnly = FALSE))
  ][1] |>
    sub("^--file=", "", x = _)),
  error = function(e) NULL
)

`%||%` <- function(a, b) if (!is.null(a)) a else b

# The registry catalogues functions referenced as `fn:` in YAML. Most live in
# recoding.R; a few derive helpers (compute_*) live in harmonize.R. Source both
# into the same isolated env so the drift check sees the full universe of
# YAML-referenceable functions.
recoding_path <- "src/r/utils/recoding.R"
harmonize_path <- "src/r/harmonize/harmonize.R"
registry_path <- "src/r/utils/recoding_registry.yml"

if (!file.exists(recoding_path)) {
  if (requireNamespace("here", quietly = TRUE)) {
    recoding_path <- here::here("src/r/utils/recoding.R")
    harmonize_path <- here::here("src/r/harmonize/harmonize.R")
    registry_path <- here::here("src/r/utils/recoding_registry.yml")
  }
}

if (!file.exists(recoding_path)) {
  stop("Cannot locate src/r/utils/recoding.R — run from repo root or install `here`")
}
if (!file.exists(registry_path)) {
  stop("Cannot locate src/r/utils/recoding_registry.yml")
}

# ---- Source recoding.R + harmonize.R into an isolated env ----------------
fn_env <- new.env()
source(recoding_path, local = fn_env)
if (file.exists(harmonize_path)) source(harmonize_path, local = fn_env)
all_objs <- ls(fn_env, all.names = TRUE)
loaded_fns <- all_objs[
  vapply(all_objs, function(n) is.function(get(n, envir = fn_env)), logical(1))
]
# Exclude private helpers (leading "."): they are not referenced in YAML `fn:`
public_fns <- loaded_fns[!startsWith(loaded_fns, ".")]
private_fns <- loaded_fns[startsWith(loaded_fns, ".")]
# Exclude engine-orchestration functions that aren't YAML `fn:` targets.
# These are loaded but not referenced from YAML's `fn:` field — they're
# the harmonization machinery itself, not recodes.
engine_orchestration_fns <- c(
  "harmonize_variable", "harmonize_all", "apply_missing", "resolve_wave_rule",
  "%||%"
)
public_fns <- setdiff(public_fns, engine_orchestration_fns)

# ---- Read registry -------------------------------------------------------
registry <- yaml::read_yaml(registry_path)
registry_names <- vapply(registry, function(e) e$fn %||% NA_character_, character(1))

# ---- Drift checks --------------------------------------------------------
missing_from_registry <- setdiff(public_fns, registry_names)
stale_in_registry     <- setdiff(registry_names, public_fns)
duplicates_in_registry <- registry_names[duplicated(registry_names)]

drift_count <- length(missing_from_registry) +
  length(stale_in_registry) +
  length(duplicates_in_registry)

if (drift_count == 0L) {
  cat("OK\n")
  cat(sprintf("  %d public functions in recoding.R (+ %d private '.' helpers excluded)\n",
              length(public_fns), length(private_fns)))
  cat(sprintf("  %d entries in recoding_registry.yml\n", length(registry_names)))
  quit(status = 0)
}

cat("DRIFT detected\n")
cat(sprintf("  recoding.R public functions: %d\n", length(public_fns)))
cat(sprintf("  registry entries:            %d\n", length(registry_names)))

if (length(missing_from_registry)) {
  cat(sprintf("\n  [%d] Functions in recoding.R with no registry entry:\n",
              length(missing_from_registry)))
  for (fn in missing_from_registry) cat("    -", fn, "\n")
}
if (length(stale_in_registry)) {
  cat(sprintf("\n  [%d] Registry entries with no corresponding function:\n",
              length(stale_in_registry)))
  for (fn in stale_in_registry) cat("    -", fn, "\n")
}
if (length(duplicates_in_registry)) {
  cat(sprintf("\n  [%d] Duplicate fn entries in registry:\n",
              length(unique(duplicates_in_registry))))
  for (fn in unique(duplicates_in_registry)) cat("    -", fn, "\n")
}

quit(status = 1)
