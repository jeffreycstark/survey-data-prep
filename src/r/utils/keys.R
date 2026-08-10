# Row-identifier integrity helpers. row_uid is the bank-wide stable row key
# (design: docs/superpowers/specs/2026-08-10-row-identifiers-design.md).

#' Hard build-time assert: row_uid present, character, unique, non-NA.
#' A broken backbone stops the pipeline; this is not report-only.
assert_row_uid <- function(df, survey) {
  if (!"row_uid" %in% names(df)) {
    stop(sprintf("[%s] row_uid column missing from final dataset", survey))
  }
  x <- df$row_uid
  if (!is.character(x)) {
    stop(sprintf("[%s] row_uid must be character, got %s", survey, class(x)[1]))
  }
  if (anyNA(x)) {
    stop(sprintf("[%s] %d NA row_uid values", survey, sum(is.na(x))))
  }
  if (anyDuplicated(x)) {
    stop(sprintf("[%s] %d duplicated row_uid values (e.g. %s)",
                 survey, sum(duplicated(x)), x[duplicated(x)][1]))
  }
  invisible(df)
}
