harmonize_vars <- function(df, mapping) {
  dplyr::rename(df, !!!mapping)
}