#!/usr/bin/env Rscript
# src/r/harmonize/test_engine_fixes.R
#
# Regression tests for the four engine defects fixed in the 2026-08-10 pass.
# Deliberately dependency-free: plain data.frames, no haven/dplyr/yaml, so it
# runs on a bare R and can sit in the data-free CI job.
#
#   Rscript src/r/harmonize/test_engine_fixes.R

source(file.path("src", "r", "harmonize", "harmonize.R"))
source(file.path("src", "r", "harmonize", "validate_spec.R"))

fails <- 0L
expect <- function(cond, msg) {
  if (isTRUE(cond)) {
    cat("  ok   ", msg, "\n")
  } else {
    cat("  FAIL ", msg, "\n")
    fails <<- fails + 1L
  }
}

waves <- list(
  w1 = data.frame(q1 = c(1, 2, 9, 3, 97)),
  w2 = data.frame(q1 = c(4, 9, 2, 98, 1))
)
convs <- list(treat_as_na = list(codes = c(97, 98, 99)))

# --------------------------------------------------------------------------
cat("\n1. `method: null` is 'unmapped', not a crash\n")
# Before: NULL == "identity" is logical(0) -> "argument is of length zero",
# swallowed by the caller's tryCatch, variable vanished from the output.
spec_null <- list(
  id = "v_null", source = list(w1 = "q1", w2 = "q1"),
  missing = list(use_convention = "treat_as_na"),
  harmonize = list(default = list(method = "identity"),
                   exceptions = list(w1 = list(method = NULL))),
  qc = list(valid_range = c(1, 10))
)
res <- tryCatch(
  harmonize_variable(spec_null, waves, convs),
  error = function(e) structure(list(), err = conditionMessage(e))
)
expect(is.null(attr(res, "err")), "no error raised")
expect(!is.null(res$w1) && all(is.na(res$w1)), "null-method wave is all NA")
expect(identical(as.numeric(res$w2), c(4, 9, 2, NA, 1)), "other waves unaffected")

# --------------------------------------------------------------------------
cat("\n2. `qc.treat_as_na` is honoured\n")
# Documented in harmonize_v1.schema.json as "Engine appends these to the
# convention codes"; nothing read it. 47 KINU variables depended on it.
spec_tan <- list(
  id = "v_tan", source = list(w1 = "q1"),
  missing = list(use_convention = "treat_as_na"),
  harmonize = list(default = list(method = "identity")),
  qc = list(valid_range = c(1, 10), treat_as_na = 9)
)
r <- harmonize_variable(spec_tan, waves["w1"], convs)
expect(identical(as.numeric(r$w1), c(1, 2, NA, 3, NA)),
       "9 removed by qc.treat_as_na, 97 by the convention")

# a code inside valid_range is the case the range gate could never rescue
spec_tan2 <- list(
  id = "v_tan2", source = list(w1 = "q1"),
  missing = list(use_convention = "treat_as_na"),
  harmonize = list(default = list(method = "identity")),
  qc = list(valid_range = c(1, 10), treat_as_na = 3)
)
r2 <- harmonize_variable(spec_tan2, waves["w1"], convs)
expect(is.na(r2$w1[4]), "in-range treat_as_na code is removed")

# --------------------------------------------------------------------------
cat("\n3. harmonize_all() iterates the YAML array form\n")
# Every one of the 140 production specs writes `variables:` as an array, so
# names() was NULL and this returned list() without erroring.
spec_arr <- list(
  missing_conventions = convs,
  variables = list(
    list(id = "a", source = list(w1 = "q1"),
         missing = list(use_convention = "treat_as_na"),
         harmonize = list(default = list(method = "identity")),
         qc = list(valid_range = c(1, 10))),
    list(id = "b", source = list(w2 = "q1"),
         missing = list(use_convention = "treat_as_na"),
         harmonize = list(default = list(method = "identity")),
         qc = list(valid_range = c(1, 10)))
  )
)
out <- harmonize_all(spec_arr, waves, silent = TRUE)
expect(length(out) == 2L, "both variables harmonized (was 0)")
expect(identical(sort(names(out)), c("a", "b")), "named by `id`")

# --------------------------------------------------------------------------
cat("\n4. check_recoding_functions() sees the array form\n")
# Same names() bug: the fn pre-flight never inspected a single variable, so a
# typo'd `fn:` sailed through and only blew up mid-run.
spec_fn <- list(
  variables = list(
    list(id = "a",
         harmonize = list(default = list(method = "r_function",
                                         fn = "definitely_not_a_function")))
  )
)
miss <- check_recoding_functions(spec_fn, registry_path = NA)
expect("definitely_not_a_function" %in% miss, "missing fn detected")

cat(sprintf("\n%s (%d failures)\n",
            if (fails == 0L) "ALL PASS" else "FAILURES", fails))
quit(status = if (fails == 0L) 0L else 1L)
