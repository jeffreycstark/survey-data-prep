# Fault-injection tests for check_key_uniqueness.R.
# Builds synthetic processed files + declarations/exemptions in a tempdir,
# runs the check as a subprocess with the KEYCHECK_* overrides, and asserts
# on exit status + report contents.
suppressMessages(library(here))

pass <- 0; fail <- 0
ok <- function(cond, label) {
  if (isTRUE(cond)) { pass <<- pass + 1; cat("  PASS ", label, "\n") }
  else { fail <<- fail + 1; cat("  FAIL ", label, "\n") }
}

td <- file.path(tempdir(), sprintf("keycheck-%d", Sys.getpid()))
dir.create(td, recursive = TRUE, showWarnings = FALSE)

write_decl <- function(entries, name = "decl") {
  p <- file.path(td, paste0(name, ".yml"))
  yaml::write_yaml(list(schema_version = 1L, declarations = entries), p); p
}
write_exempt <- function(entries, name = "exempt") {
  p <- file.path(td, paste0(name, ".yml"))
  yaml::write_yaml(list(schema_version = 1L, exemptions = entries), p); p
}
run_check <- function(decl, exempt) {
  res <- suppressWarnings(system2(
    "Rscript", here::here("src/r/audit/check_key_uniqueness.R"),
    stdout = TRUE, stderr = TRUE,
    env = c(paste0("KEYCHECK_DATA_DIR=", td),
            paste0("KEYCHECK_DECLARATIONS=", decl),
            paste0("KEYCHECK_EXEMPTIONS=", exempt))))
  list(status = attr(res, "status") %||% 0L, out = paste(res, collapse = "\n"))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

mk <- function(n, dup_uid = FALSE, na_uid = FALSE, key_dups = 0L) {
  uid <- sprintf("t.w1.%06d", seq_len(n))
  if (dup_uid) uid[2] <- uid[1]
  if (na_uid) uid[2] <- NA_character_
  key <- seq_len(n)
  if (key_dups > 0) key[seq_len(key_dups) + 1] <- key[1]
  data.frame(row_uid = uid, wave = 1L, nid = key, stringsAsFactors = FALSE)
}

decl <- write_decl(list(list(survey = "tsurv", key = list("wave", "nid"))))
ex_none <- write_exempt(list(), name = "exempt_none")
ex_two  <- write_exempt(list(list(survey = "tsurv", max_dup_rows = 2L, reason = "known pair")), name = "exempt_two")

cat("=== T1: clean file passes ===\n")
saveRDS(mk(5), file.path(td, "tsurv_harmonized.rds"))
r <- run_check(decl, ex_none)
ok(r$status == 0, "exit 0 on clean")
ok(grepl("row_uid.*unique", r$out), "row_uid OK line present")

cat("=== T2: duplicated row_uid is a hard error ===\n")
saveRDS(mk(5, dup_uid = TRUE), file.path(td, "tsurv_harmonized.rds"))
r <- run_check(decl, ex_none)
ok(r$status == 1, "exit 1 on dup row_uid")

cat("=== T3: NA row_uid is a hard error ===\n")
saveRDS(mk(5, na_uid = TRUE), file.path(td, "tsurv_harmonized.rds"))
r <- run_check(decl, ex_none)
ok(r$status == 1, "exit 1 on NA row_uid")

cat("=== T4: unexempted native dup errors; exempted passes ===\n")
saveRDS(mk(6, key_dups = 2L), file.path(td, "tsurv_harmonized.rds"))
r <- run_check(decl, ex_none)
ok(r$status == 1, "exit 1 unexempted")
r <- run_check(decl, ex_two)
ok(r$status == 0, "exit 0 within exemption budget")
ok(grepl("EXEMPT", r$out), "EXEMPT status emitted")

cat("=== T5: exemption does not cover a wider violation ===\n")
saveRDS(mk(8, key_dups = 3L), file.path(td, "tsurv_harmonized.rds"))
r <- run_check(decl, ex_two)
ok(r$status == 1, "3 surplus vs budget 2 -> exit 1")
ok(grepl("exceeds exemption budget", r$out), "budget-exceeded message")

cat("=== T6: NA key rows are skipped, not asserted ===\n")
d <- mk(5); d$nid[1:2] <- NA
saveRDS(d, file.path(td, "tsurv_harmonized.rds"))
r <- run_check(decl, ex_none)
ok(r$status == 0, "NA-key rows skipped")
ok(grepl("2 incomplete skipped", r$out), "incomplete count reported")

cat("=== T7: absent file is SKIP, not error ===\n")
decl2 <- write_decl(list(list(survey = "ghost", key = list("wave", "nid"))), name = "decl_ghost")
r <- run_check(decl2, ex_none)
ok(r$status == 0, "missing processed file -> skip, exit 0")
ok(grepl("SKIP", r$out), "SKIP emitted")

unlink(td, recursive = TRUE)
cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) quit(status = 1)
