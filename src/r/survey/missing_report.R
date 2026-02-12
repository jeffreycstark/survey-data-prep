missing_report <- function(df) {
  tibble::tibble(
    variable = names(df),
    missing_pct = colMeans(is.na(df))
  )
}