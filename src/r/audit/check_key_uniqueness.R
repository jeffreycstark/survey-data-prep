# check_key_uniqueness.R — do the declared row keys actually identify rows?
# -----------------------------------------------------------------------------
# Two assertions per survey, against data/processed/<survey>_harmonized.rds:
#
#   1. row_uid (HARD): present, character, non-NA, unique. The bank-wide
#      stable backbone minted by stack_harmonized_wide(); a violation here is
#      always an ERROR — no exemptions exist for the backbone.
#   2. Declared native key (report level): the columns listed in
#      src/config/_audit/key_declarations.yml must identify rows uniquely on
#      COMPLETE rows (every key column non-NA), up to the per-survey
#      allowance in key_uniqueness_exemptions.yml. Surplus rows beyond the
#      allowance are ERRORS; within it, EXEMPT. Incomplete rows are counted
#      and reported, never asserted (partial-coverage IDs skip waves by
#      design).
#
# Born from the 2026-08-09 ABS idnumber bug: 357 IDs deleted by a missing-
# code convention, invisible because nothing asserted that an ID identifies
# exactly one row. Design: docs/superpowers/specs/2026-08-10-row-identifiers-design.md
#
# Usage:
#   Rscript src/r/audit/check_key_uniqueness.R            # all declared surveys
#   KEYCHECK_DATA_DIR=<dir> Rscript ...                   # test override
#
# Exit: 0 clean/exempt-only · 1 any error · 2 config problem
# Report: audit/reports/key_uniqueness.csv
# -----------------------------------------------------------------------------

suppressMessages({library(here); library(yaml)})
source(here::here("src/r/utils/keys.R"))

.DATA_DIR <- Sys.getenv("KEYCHECK_DATA_DIR", here::here("data", "processed"))
.DECLS    <- Sys.getenv("KEYCHECK_DECLARATIONS",
                        here::here("src/config/_audit/key_declarations.yml"))
.EXEMPTS  <- Sys.getenv("KEYCHECK_EXEMPTIONS",
                        here::here("src/config/_audit/key_uniqueness_exemptions.yml"))

decls <- tryCatch(read_yaml(.DECLS), error = function(e) NULL)
exempts <- tryCatch(read_yaml(.EXEMPTS), error = function(e) NULL)
if (is.null(decls) || is.null(decls$declarations)) {
  cat("CONFIG ERROR: cannot read declarations at", .DECLS, "\n"); quit(status = 2)
}
if (is.null(exempts)) {
  cat("CONFIG ERROR: cannot read exemptions at", .EXEMPTS, "\n"); quit(status = 2)
}
allow <- setNames(
  vapply(exempts$exemptions, function(e) as.integer(e$max_dup_rows), 1L),
  vapply(exempts$exemptions, function(e) e$survey, "")
)
reasons <- setNames(
  vapply(exempts$exemptions, function(e) gsub("\\s+", " ", e$reason), ""),
  vapply(exempts$exemptions, function(e) e$survey, "")
)

rows <- list()
n_err <- 0L; n_exempt <- 0L; n_ok <- 0L; n_skip <- 0L

emit <- function(survey, check, status, detail) {
  rows[[length(rows) + 1]] <<- data.frame(
    survey = survey, check = check, status = status, detail = detail)
  tag <- c(OK = "OK    ", EXEMPT = "EXEMPT", ERROR = "ERROR ", SKIP = "SKIP  ")[status]
  cat(sprintf("  %s %-16s %-10s %s\n", tag, survey, check, detail))
  switch(status,
         OK = n_ok <<- n_ok + 1L, EXEMPT = n_exempt <<- n_exempt + 1L,
         ERROR = n_err <<- n_err + 1L, SKIP = n_skip <<- n_skip + 1L)
}

for (d in decls$declarations) {
  sv <- d$survey
  path <- file.path(.DATA_DIR, paste0(gsub("-", "_", sv), "_harmonized.rds"))
  if (!file.exists(path)) {
    emit(sv, "presence", "SKIP", sprintf("no processed file (%s)", basename(path)))
    next
  }
  df <- readRDS(path)

  # ---- 1. row_uid backbone (hard) ----
  uid_err <- tryCatch({ assert_row_uid(df, sv); NULL },
                      error = function(e) conditionMessage(e))
  if (is.null(uid_err)) {
    emit(sv, "row_uid", "OK", sprintf("unique + non-NA on %s rows",
                                      format(nrow(df), big.mark = ",")))
  } else {
    emit(sv, "row_uid", "ERROR", uid_err)
  }

  # ---- 2. declared native key (report level, exemption-aware) ----
  keycols <- unlist(d$key)
  missing_cols <- setdiff(keycols, names(df))
  if (length(missing_cols)) {
    emit(sv, "native_key", "ERROR",
         sprintf("declared key column(s) absent: %s", paste(missing_cols, collapse = ", ")))
    next
  }
  complete <- stats::complete.cases(df[keycols])
  n_incomplete <- sum(!complete)
  k <- do.call(paste, c(df[complete, keycols, drop = FALSE], sep = "\r"))
  surplus <- length(k) - length(unique(k))
  budget <- if (sv %in% names(allow)) allow[[sv]] else 0L
  keylab <- paste(keycols, collapse = "+")
  if (surplus == 0L) {
    emit(sv, "native_key", "OK",
         sprintf("%s unique on %s complete rows (%s incomplete skipped)",
                 keylab, format(sum(complete), big.mark = ","),
                 format(n_incomplete, big.mark = ",")))
  } else if (surplus <= budget) {
    emit(sv, "native_key", "EXEMPT",
         sprintf("%s: %d surplus row(s) within exemption budget %d — %s",
                 keylab, surplus, budget, reasons[[sv]]))
  } else {
    emit(sv, "native_key", "ERROR",
         sprintf("%s: %d surplus duplicate row(s), exceeds exemption budget %d — investigate before exempting",
                 keylab, surplus, budget))
  }
}

out <- do.call(rbind, rows)
rep_path <- here::here("audit", "reports", "key_uniqueness.csv")
dir.create(dirname(rep_path), showWarnings = FALSE, recursive = TRUE)
write.csv(out, rep_path, row.names = FALSE)

cat(sprintf("\nSummary: %d ok, %d exempt, %d error, %d skip. Report: %s\n",
            n_ok, n_exempt, n_err, n_skip, rep_path))
if (n_err > 0) {
  cat("A key that does not identify rows silently corrupts every join made\n")
  cat("on it. Fix the pipeline or, for a verified release-file artifact,\n")
  cat("exempt WITH A REASON in key_uniqueness_exemptions.yml.\n")
  quit(status = 1)
}
