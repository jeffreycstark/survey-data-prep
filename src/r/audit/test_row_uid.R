# Fault-injection tests for engine-minted row_uid.
library(here)
source(here::here("src/r/data_prep_modules/2_harmonize_all.R"))

pass <- 0; fail <- 0
ok <- function(cond, label) {
  if (isTRUE(cond)) { pass <<- pass + 1; cat("  PASS ", label, "\n") }
  else { fail <<- fail + 1; cat("  FAIL ", label, "\n") }
}

# Synthetic two-wave survey: 3 and 2 rows.
waves <- list(w1 = data.frame(q1 = c(1, 2, 3)), w2 = data.frame(q1 = c(4, 5)))
results <- list(testspec = list(
  concept = "t",
  variables = list(v1 = list(w1 = c(1, 2, 3), w2 = c(4, 5)))))

out <- stack_harmonized_wide(results, waves, survey = "synth")

cat("=== T1: format and uniqueness ===\n")
ok(identical(out$w1$row_uid, c("synth.w1.000001", "synth.w1.000002", "synth.w1.000003")),
   "w1 row_uid exact format")
ok(identical(out$w2$row_uid, c("synth.w2.000001", "synth.w2.000002")),
   "w2 row_uid exact format")
ok(!"row_id" %in% c(names(out$w1), names(out$w2)), "row_id no longer emitted")
ok(is.character(out$w1$row_uid), "row_uid is character")

cat("=== T2: stability — same input, same ids ===\n")
out2 <- stack_harmonized_wide(results, waves, survey = "synth")
ok(identical(out$w1$row_uid, out2$w1$row_uid), "rebuild yields identical ids")

cat("=== T3: missing survey argument fails loudly ===\n")
r <- tryCatch({ stack_harmonized_wide(results, waves); "no-error" },
              error = function(e) "error")
ok(r == "error", "omitting survey is an error")

cat("=== T4: assert_row_uid ===\n")
source(here::here("src/r/utils/keys.R"))
good <- data.frame(row_uid = c("s.w1.000001", "s.w1.000002"), stringsAsFactors = FALSE)
ok(identical(assert_row_uid(good, "s"), good), "clean frame passes through")
r <- tryCatch({ assert_row_uid(data.frame(x = 1), "s"); "no-error" }, error = function(e) "error")
ok(r == "error", "missing column stops")
r <- tryCatch({ assert_row_uid(data.frame(row_uid = c("a", "a")), "s"); "no-error" }, error = function(e) "error")
ok(r == "error", "duplicate stops")
r <- tryCatch({ assert_row_uid(data.frame(row_uid = c("a", NA)), "s"); "no-error" }, error = function(e) "error")
ok(r == "error", "NA stops")

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) quit(status = 1)
