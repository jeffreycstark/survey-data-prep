#' Cross-wave party lineage helper
#'
#' Joins per-respondent (country, wave, party-code) rows to the cross-wave
#' party lineage crosswalk at data/processed/party_id_crosswalk.csv. Lets
#' papers add party_lineage and coalition columns in one call rather than
#' duplicating the join logic each time.
#'
#' Crosswalk currently covers Korea / Taiwan / Thailand × W2-W6. Other
#' (country x wave) combinations get NA + a one-time warning.

suppressPackageStartupMessages({
  library(dplyr)
  library(here)
  library(readr)
})

#' @param df          Data frame with country, wave, and a party-code column.
#' @param country_col String name of the country column. Accepts integer codes
#'                    (1=Japan, 3=Korea, 7=Taiwan, 8=Thailand, ...) or
#'                    character names ("Korea", "Taiwan", "Thailand").
#' @param wave_col    String name of the wave column. Accepts "w2"/"W2"/2.
#' @param code_col    String name of the per-wave party-code column.
#' @param crosswalk_path Path to the crosswalk CSV/RDS. Defaults to
#'                       here("data/processed/party_id_crosswalk.csv").
#' @param country_map_path Path to the country-code lookup CSV. Defaults to
#'                         here("data/lookups/abs_country_codes.csv").
#' @param columns     Crosswalk columns to attach. Default
#'                    c("party_lineage", "coalition"). May also include
#'                    "party_name".
#' @param suffix      Optional suffix appended to attached column names. NULL
#'                    means no suffix; conflicts then error.
#'
#' @return df with the requested columns appended.
join_party_crosswalk <- function(df,
                                 country_col,
                                 wave_col,
                                 code_col,
                                 crosswalk_path = NULL,
                                 country_map_path = NULL,
                                 columns = c("party_lineage", "coalition"),
                                 suffix = NULL) {

  stopifnot(
    is.data.frame(df),
    is.character(country_col), length(country_col) == 1,
    is.character(wave_col),    length(wave_col) == 1,
    is.character(code_col),    length(code_col) == 1,
    is.character(columns),     length(columns) >= 1
  )

  required_cols <- c(country_col, wave_col, code_col)
  missing_in_df <- setdiff(required_cols, names(df))
  if (length(missing_in_df) > 0) {
    stop(
      "join_party_crosswalk(): df is missing required column(s): ",
      paste(missing_in_df, collapse = ", ")
    )
  }

  if (is.null(crosswalk_path)) {
    crosswalk_path <- here::here("data", "processed", "party_id_crosswalk.csv")
  }
  if (!file.exists(crosswalk_path)) {
    stop("join_party_crosswalk(): crosswalk file not found at ", crosswalk_path)
  }

  if (is.null(country_map_path)) {
    country_map_path <- here::here("data", "lookups", "abs_country_codes.csv")
  }
  if (!file.exists(country_map_path)) {
    stop("join_party_crosswalk(): country map not found at ", country_map_path)
  }

  crosswalk <- readr::read_csv(crosswalk_path, show_col_types = FALSE)
  cw_required <- c("country", "code", "wave", columns)
  cw_missing <- setdiff(cw_required, names(crosswalk))
  if (length(cw_missing) > 0) {
    stop(
      "join_party_crosswalk(): crosswalk lacks column(s): ",
      paste(cw_missing, collapse = ", ")
    )
  }

  country_map <- readr::read_csv(country_map_path, show_col_types = FALSE)
  if (!all(c("country_code", "country_name") %in% names(country_map))) {
    stop(
      "join_party_crosswalk(): country map must have columns ",
      "country_code and country_name"
    )
  }

  attach_cols <- columns
  if (!is.null(suffix)) {
    new_names <- paste0(attach_cols, suffix)
  } else {
    new_names <- attach_cols
  }
  conflicts <- intersect(new_names, setdiff(names(df), required_cols))
  if (length(conflicts) > 0) {
    stop(
      "join_party_crosswalk(): output column(s) already exist in df: ",
      paste(conflicts, collapse = ", "),
      ". Pass a `suffix` to disambiguate."
    )
  }

  raw_country <- df[[country_col]]
  if (is.numeric(raw_country)) {
    name_lookup <- setNames(country_map$country_name, country_map$country_code)
    country_norm <- unname(name_lookup[as.character(raw_country)])
  } else {
    country_norm <- as.character(raw_country)
  }

  raw_wave <- df[[wave_col]]
  wave_norm <- toupper(as.character(raw_wave))
  wave_norm <- sub("^W", "", wave_norm)
  wave_norm <- ifelse(is.na(wave_norm) | wave_norm == "NA",
                      NA_character_,
                      paste0("W", wave_norm))

  cw_combos <- unique(crosswalk[, c("country", "wave")])
  cw_keyset <- paste(cw_combos$country, cw_combos$wave, sep = "|")

  df_combos <- unique(data.frame(
    country = country_norm,
    wave    = wave_norm,
    stringsAsFactors = FALSE
  ))
  df_combos <- df_combos[!is.na(df_combos$country) & !is.na(df_combos$wave), ]
  df_combos$key <- paste(df_combos$country, df_combos$wave, sep = "|")

  missing_combos <- df_combos[!df_combos$key %in% cw_keyset, ]
  if (nrow(missing_combos) > 0) {
    keys <- paste(missing_combos$country, missing_combos$wave, sep = " ")
    n_rows_missing <- sum(
      paste(country_norm, wave_norm, sep = "|") %in% missing_combos$key
    )
    warning(
      "join_party_crosswalk(): the following (country x wave) combinations ",
      "are not in the crosswalk and will receive NA for ",
      paste(new_names, collapse = ", "), ": ",
      paste(keys, collapse = "; "),
      ". Affected rows: ", n_rows_missing,
      ". To extend coverage, edit data/processed/create_party_crosswalk.R.",
      call. = FALSE
    )
  }

  join_df <- data.frame(
    .__country = country_norm,
    .__wave    = wave_norm,
    .__code    = df[[code_col]],
    .__row     = seq_len(nrow(df)),
    stringsAsFactors = FALSE
  )

  cw_slim <- crosswalk[, c("country", "code", "wave", attach_cols)]
  names(cw_slim)[seq_len(3)] <- c(".__country", ".__code", ".__wave")

  joined <- dplyr::left_join(
    join_df,
    cw_slim,
    by = c(".__country", ".__wave", ".__code")
  )
  joined <- joined[order(joined$.__row), ]

  out <- df
  for (i in seq_along(attach_cols)) {
    out[[new_names[i]]] <- joined[[attach_cols[i]]]
  }

  out
}
