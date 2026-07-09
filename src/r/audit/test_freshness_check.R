#!/usr/bin/env Rscript
#' Fault-injection tests for src/r/audit/06_check_freshness.R
#'
#' Run with:
#'   Rscript src/r/audit/test_freshness_check.R
#'
#' The check is only worth trusting if each fault class provably makes it fire.
#' Every test below builds a throwaway survey fixture (its own spec dir, input,
#' output and manifest), asserts FRESH, injects exactly one fault, and asserts
#' the verdict flips. Nothing touches real surveys or data/processed/.
#'
#' Fault classes covered:
#'   1. baseline                       -> FRESH
#'   2. a recorded spec is edited      -> STALE   (the KIPA class)
#'   3. a NEW spec is added, unbuilt   -> STALE   (06_check_determinism.R misses this)
#'   4. a recorded spec is deleted     -> STALE
#'   5. an engine file is edited       -> STALE
#'   6. a recorded input is edited     -> STALE
#'   7. the harmonized output is edited-> TAMPERED
#'   8. STALE outranks TAMPERED when both hold
#'   9. no manifest                    -> SKIP
#'  10. unreadable manifest            -> STALE (fails closed, never FRESH)

Sys.setenv(FRESHNESS_SOURCE_ONLY = "1")

suppressPackageStartupMessages({
  library(here)
  library(jsonlite)
})

source(here::here("src", "r", "audit", "06_check_freshness.R"))

# ---------------------------------------------------------------------------
# Tiny assertion harness (mirrors the other audit test scripts).
# ---------------------------------------------------------------------------
.pass <- 0L
.fail <- 0L
expect <- function(cond, label) {
  if (isTRUE(cond)) {
    cat(sprintf("  [PASS] %s\n", label)); .pass <<- .pass + 1L
  } else {
    cat(sprintf("  [FAIL] %s\n", label)); .fail <<- .fail + 1L
  }
}

# ---------------------------------------------------------------------------
# Fixture: a self-contained fake survey. We hand-write the manifest in the
# real schema rather than calling write_manifest(), because write_manifest()
# derives spec paths from the real src/config tree.
#
# `spec_dir` is planted under a temp root; check_survey_freshness() resolves
# added-specs via list_survey_specs(), which reads the REAL config tree, so
# the fixture survey name is one that has no real spec dir. That makes
# .added_specs() return character() and lets tests 2/4-10 isolate their fault.
# Test 3 exercises added-specs against a real survey separately.
# ---------------------------------------------------------------------------
make_fixture <- function() {
  root <- file.path(tempdir(), paste0("freshfix_", as.integer(runif(1, 1e6, 9e6))))
  dir.create(root, recursive = TRUE, showWarnings = FALSE)

  spec  <- file.path(root, "core.yml")
  input <- file.path(root, "raw.csv")
  outp  <- file.path(root, "harmonized.rds")
  writeLines(c("variables:", "  - id: x"), spec)
  writeLines("a,b\n1,2", input)
  saveRDS(data.frame(x = 1:3), outp)

  # A real engine file, so the engine check has something true to compare.
  engine_rel <- "src/r/utils/recoding.R"

  sha <- function(p) digest::digest(file = p, algo = "sha256")

  manifest <- list(
    run_id = "test", timestamp_utc = "2026-01-01T00:00:00Z",
    git_commit = "deadbeef", git_dirty = FALSE, schema_version = 1L,
    inputs  = list(list(path = input, sha256 = sha(input))),
    specs   = list(list(path = spec,  sha256 = sha(spec), n_variables = 1L)),
    outputs = list(list(path = outp,  sha256 = sha(outp), n_rows = 3L, n_cols = 1L)),
    engine_versions = setNames(list(sha(here::here(engine_rel))), engine_rel)
  )
  mpath <- file.path(root, "manifest.json")
  jsonlite::write_json(manifest, mpath, auto_unbox = TRUE, null = "null")

  list(root = root, spec = spec, input = input, output = outp, manifest = mpath)
}

verdict_of <- function(fx, survey = "no-such-survey") {
  check_survey_freshness(survey, manifest_path = fx$manifest)$verdict
}

# ---------------------------------------------------------------------------
cat("=== test 1: baseline fixture is FRESH ===\n")
fx <- make_fixture()
expect(verdict_of(fx) == "FRESH", "untouched fixture -> FRESH")

cat("\n=== test 2: recorded spec edited -> STALE (the KIPA class) ===\n")
fx <- make_fixture()
cat("\n# gated_waves: [2016]\n", file = fx$spec, append = TRUE)
r <- check_survey_freshness("no-such-survey", manifest_path = fx$manifest)
expect(r$verdict == "STALE", "edited spec -> STALE")
expect(any(grepl("spec drift", r$rebuild)), "reason names 'spec drift'")

cat("\n=== test 3: NEW spec added but never harmonized -> STALE ===\n")
# Use a real survey so list_survey_specs() resolves, and drop the real specs
# from the manifest's recorded set to simulate 'one spec never harmonized'.
real_specs <- list_survey_specs("kipa-corruption")
expect(length(real_specs) > 1L, "kipa-corruption has >1 spec on disk")
fx3 <- make_fixture()
m <- jsonlite::read_json(fx3$manifest, simplifyVector = FALSE)
sha <- function(p) digest::digest(file = p, algo = "sha256")
# Record ALL BUT ONE real spec; the omitted one must surface as ADDED.
recorded <- lapply(real_specs[-1], function(p) list(path = p, sha256 = sha(p)))
m$specs <- recorded
jsonlite::write_json(m, fx3$manifest, auto_unbox = TRUE, null = "null")
r3 <- check_survey_freshness("kipa-corruption", manifest_path = fx3$manifest)
expect(r3$verdict == "STALE", "unrecorded spec -> STALE")
expect(any(grepl("spec ADDED", r3$rebuild)), "reason names 'spec ADDED'")
# And with every real spec recorded, the added-set is empty again.
m$specs <- lapply(real_specs, function(p) list(path = p, sha256 = sha(p)))
jsonlite::write_json(m, fx3$manifest, auto_unbox = TRUE, null = "null")
r3b <- check_survey_freshness("kipa-corruption", manifest_path = fx3$manifest)
expect(!any(grepl("spec ADDED", r3b$rebuild)), "all specs recorded -> no ADDED")

cat("\n=== test 4: recorded spec deleted -> STALE ===\n")
fx <- make_fixture(); unlink(fx$spec)
r <- check_survey_freshness("no-such-survey", manifest_path = fx$manifest)
expect(r$verdict == "STALE", "deleted spec -> STALE")
expect(any(grepl("spec missing", r$rebuild)), "reason names 'spec missing'")

cat("\n=== test 5: engine file edited -> STALE ===\n")
fx <- make_fixture()
m <- jsonlite::read_json(fx$manifest, simplifyVector = FALSE)
m$engine_versions[["src/r/utils/recoding.R"]] <- strrep("0", 64)  # corrupt sha
jsonlite::write_json(m, fx$manifest, auto_unbox = TRUE, null = "null")
r <- check_survey_freshness("no-such-survey", manifest_path = fx$manifest)
expect(r$verdict == "STALE", "engine drift -> STALE")
expect(any(grepl("engine drift", r$rebuild)), "reason names 'engine drift'")

cat("\n=== test 6: recorded input edited -> STALE ===\n")
fx <- make_fixture()
cat("3,4\n", file = fx$input, append = TRUE)
r <- check_survey_freshness("no-such-survey", manifest_path = fx$manifest)
expect(r$verdict == "STALE", "input drift -> STALE")
expect(any(grepl("input drift", r$rebuild)), "reason names 'input drift'")

cat("\n=== test 7: harmonized output edited -> TAMPERED ===\n")
fx <- make_fixture()
saveRDS(data.frame(x = 1:4), fx$output)   # output only; specs/inputs untouched
r <- check_survey_freshness("no-such-survey", manifest_path = fx$manifest)
expect(r$verdict == "TAMPERED", "output drift -> TAMPERED (not STALE)")
expect(any(grepl("output drift", r$tamper)), "reason names 'output drift'")
expect(length(r$rebuild) == 0L, "TAMPERED carries no rebuild triggers")

cat("\n=== test 8: spec AND output both changed -> STALE wins ===\n")
fx <- make_fixture()
cat("\n# touched\n", file = fx$spec, append = TRUE)
saveRDS(data.frame(x = 1:9), fx$output)
r <- check_survey_freshness("no-such-survey", manifest_path = fx$manifest)
expect(r$verdict == "STALE", "STALE outranks TAMPERED")
expect(length(r$tamper) > 0L, "tamper triggers still recorded for reporting")

cat("\n=== test 9: no manifest -> SKIP ===\n")
r <- check_survey_freshness("no-such-survey",
                            manifest_path = file.path(tempdir(), "absent.json"))
expect(r$verdict == "SKIP", "missing manifest -> SKIP")

cat("\n=== test 10: unreadable manifest fails closed (never FRESH) ===\n")
bad <- file.path(tempdir(), "bad_manifest.json")
writeLines("{ this is not json", bad)
r <- check_survey_freshness("no-such-survey", manifest_path = bad)
expect(r$verdict == "STALE", "corrupt manifest -> STALE, not FRESH")

cat(sprintf("\n%s — %d passed, %d failed\n",
            if (.fail == 0L) "ALL PASS" else "FAILURES", .pass, .fail))
if (.fail > 0L) quit(status = 1)
quit(status = 0)
