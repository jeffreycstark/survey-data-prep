#!/usr/bin/env Rscript
# src/r/audit/test_module_coverage.R
#
# Fault-injection tests for Layer 7 (module coverage).
# Run:  Rscript src/r/audit/test_module_coverage.R
# Exit: 0 if all pass, 1 otherwise.
#
# The point of this layer is to catch a module that NOTHING audits. These tests
# therefore inject the exact failure that motivated it — an unregistered module
# — and assert the check goes hard, not quiet.

suppressPackageStartupMessages({ library(here); library(yaml) })
source(here::here("src", "r", "audit", "07_module_coverage.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

tmp <- file.path(tempdir(), paste0("modcov_", as.integer(runif(1, 1e6, 9e6))))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

write_lists <- function(supported, fresh) {
  ra <- file.path(tmp, "run_all.R"); fr <- file.path(tmp, "freshness.R")
  writeLines(c(".SUPPORTED_SURVEYS <- c(",
               paste0('  ', paste(sprintf('"%s"', supported), collapse = ", ")),
               ")"), ra)
  writeLines(c(".FRESHNESS_SURVEYS <- c(",
               paste0('  ', paste(sprintf('"%s"', fresh), collapse = ", ")),
               ")"), fr)
  list(ra = ra, fr = fr)
}

write_ex <- function(entries) {
  p <- file.path(tmp, "ex.yml")
  yaml::write_yaml(list(schema_version = 1, exempt_modules = entries), p)
  p
}

run <- function(modules, supported, fresh, entries) {
  f <- write_lists(supported, fresh)
  check_module_coverage(module_dir = tmp, exemptions_path = write_ex(entries),
                        run_all_path = f$ra, freshness_path = f$fr,
                        modules = modules)
}

cat("\n── Layer 7 fault injection ──\n")

# 1. Clean baseline.
r <- run(c("abs", "wvs"), c("abs", "wvs"), c("abs", "wvs"), list())
ok(length(r$hard) == 0 && length(r$soft) == 0, "clean: all modules registered -> no findings")

# 2. THE MOTIVATING BUG — a module on disk that no list knows about.
r <- run(c("abs", "wvs", "marpor"), c("abs", "wvs"), c("abs", "wvs"), list())
ok(length(r$hard) == 1, "unregistered module -> HARD finding")
ok(grepl("marpor", r$hard[1]), "hard finding names the offending module")
ok(grepl("NO audit coverage", r$hard[1]), "finding states there is no coverage")

# 3. Same module, but properly exempted -> silent.
r <- run(c("abs", "marpor"), "abs", "abs",
         list(list(module = "marpor", reason = "not a survey", still_required = NULL)))
ok(length(r$hard) == 0, "exempted module with a reason -> no hard finding")

# 4. Exemption without a reason is not a real exemption.
r <- run(c("abs", "marpor"), "abs", "abs",
         list(list(module = "marpor", reason = "", still_required = NULL)))
ok(any(grepl("without a reason", r$hard)), "reasonless exemption -> HARD finding")

# 5. THE DANGEROUS DIRECTION — a survey audited by run_all but dropped from the
#    freshness list. It looks covered while its data can silently rot.
r <- run(c("abs", "wvs"), c("abs", "wvs"), "abs", list())
ok(any(grepl("MISSING from .FRESHNESS_SURVEYS", r$hard)),
   "audited survey absent from freshness list -> HARD finding")
ok(any(grepl("wvs", r$hard)), "finding names the un-pre-flighted survey")

# 6. The other direction is LEGITIMATE, not drift: freshness covers more than
#    the survey checks, because non-survey modules can still go stale. Allowed
#    only when the extra entry is a registered exemption.
r <- run(c("abs", "vdem"), "abs", c("abs", "vdem"),
         list(list(module = "vdem", reason = "not a survey", still_required = "freshness")))
ok(length(r$hard) == 0, "freshness-only entry that IS exempted -> no finding")

# 6b. ...but an unexplained freshness-only entry is a typo or stale config.
r <- run("abs", "abs", c("abs", "typo-survey"), list())
ok(any(grepl("no run_all registration and no", r$hard)),
   "unexplained freshness-only entry -> HARD finding")

# 7. still_required: freshness, but module absent from the freshness list.
r <- run(c("abs", "vdem"), "abs", "abs",
         list(list(module = "vdem", reason = "not a survey", still_required = "freshness")))
ok(length(r$hard) == 0, "residual-coverage gap is SOFT, not hard")
ok(any(grepl("NOT staleness-checked", r$soft)), "residual gap reported as a soft finding")

# 8. Satisfying still_required clears the soft finding.
r <- run(c("abs", "vdem"), "abs", c("abs", "vdem"),
         list(list(module = "vdem", reason = "not a survey", still_required = "freshness")))
ok(length(r$soft) == 0, "module present in freshness list -> soft finding clears")

# 9. Stale exemption for a module that no longer exists.
r <- run("abs", "abs", "abs",
         list(list(module = "ghost", reason = "gone", still_required = NULL)))
ok(any(grepl("stale config", r$soft)), "exemption for absent module -> soft finding")

# 10. Unparseable source file is a config error, not a false pass.
f <- write_lists("abs", "abs")
writeLines("nothing here", f$ra)
r <- check_module_coverage(module_dir = tmp, exemptions_path = write_ex(list()),
                           run_all_path = f$ra, freshness_path = f$fr, modules = "abs")
ok(isTRUE(r$config_error), "unparseable run_all.R -> config error, never a silent pass")

cat(sprintf("\n  %d passed, %d failed\n", .pass, .fail))
quit(status = if (.fail > 0) 1 else 0)
