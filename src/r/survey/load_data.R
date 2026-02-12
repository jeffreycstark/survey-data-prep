load_survey <- function(path, format = c("sav", "csv")) {
  format <- match.arg(format)

  if (format == "sav") {
    haven::read_sav(path)
  } else {
    readr::read_csv(path, show_col_types = FALSE)
  }
}