# search_labels.R
# Fast variable/label search across raw survey files (ABS, WVS, LBS).
# Reads only metadata — does not load full datasets into memory.
#
# Usage:
#   source("src/r/utils/search_labels.R")
#   extract_labels("trust", get_wave_files("abs"))
#   extract_labels(c("democracy", "satisfaction"), get_wave_files("lbs"))
#   extract_labels("trust", get_wave_files("wvs"))
#   extract_labels("government", get_wave_files("all"))

# ---------------------------------------------------------------------------
# get_wave_files: return named vector of raw file paths for a survey
# ---------------------------------------------------------------------------

get_wave_files <- function(survey = c("abs", "wvs", "lbs", "all")) {
  survey <- match.arg(survey)
  base <- here::here("data")

  abs_files <- function() {
    abs_dir <- file.path(base, "abs", "raw")
    files <- c()
    for (w in 1:5) {
      d <- file.path(abs_dir, paste0("wave", w))
      sav <- list.files(d, pattern = "\\.sav$", ignore.case = TRUE, full.names = TRUE)
      if (length(sav) > 0) files <- c(files, setNames(sav[1], paste0("abs_w", w)))
    }
    # Wave 6: all country files
    w6_dir <- file.path(abs_dir, "wave6")
    w6_files <- list.files(w6_dir, pattern = "\\.sav$", ignore.case = TRUE, full.names = TRUE)
    if (length(w6_files) > 0) {
      names(w6_files) <- paste0("abs_w6_", gsub("\\.sav$", "", basename(w6_files), ignore.case = TRUE))
      files <- c(files, w6_files)
    }
    files
  }

  wvs_files <- function() {
    wvs_dir <- file.path(base, "wvs", "raw")
    files <- c()
    for (w in c("wave6", "wave7")) {
      d <- file.path(wvs_dir, w)
      pq <- list.files(d, pattern = "\\.parquet$", full.names = TRUE)
      sav <- list.files(d, pattern = "\\.sav$", ignore.case = TRUE, full.names = TRUE)
      dta <- list.files(d, pattern = "\\.dta$", ignore.case = TRUE, full.names = TRUE)
      f <- c(pq, sav, dta)
      if (length(f) > 0) {
        wnum <- gsub("wave", "", w)
        files <- c(files, setNames(f[1], paste0("wvs_w", wnum)))
      }
    }
    files
  }

  lbs_files <- function() {
    lbs_dir <- file.path(base, "lbs", "raw")
    years <- list.dirs(lbs_dir, recursive = FALSE, full.names = FALSE)
    years <- years[grepl("^\\d{4}$", years)]
    files <- c()
    for (yr in sort(years)) {
      d <- file.path(lbs_dir, yr)
      eng <- list.files(d, pattern = "_Eng.*\\.sav$", ignore.case = TRUE, full.names = TRUE)
      if (length(eng) > 0) {
        files <- c(files, setNames(eng[1], paste0("lbs_", yr)))
      } else {
        sav <- list.files(d, pattern = "\\.sav$", ignore.case = TRUE, full.names = TRUE)
        if (length(sav) > 0) files <- c(files, setNames(sav[1], paste0("lbs_", yr)))
      }
    }
    files
  }

  switch(survey,
    abs = abs_files(),
    wvs = wvs_files(),
    lbs = lbs_files(),
    all = c(abs_files(), wvs_files(), lbs_files())
  )
}

# ---------------------------------------------------------------------------
# extract_labels: search variable names + labels across raw survey files
# ---------------------------------------------------------------------------

extract_labels <- function(search_term, file_vector, match_type = "AND", print_output = TRUE) {

  if (!requireNamespace("haven", quietly = TRUE)) stop("Package 'haven' is required.", call. = FALSE)
  if (!requireNamespace("labelled", quietly = TRUE)) stop("Package 'labelled' is required.", call. = FALSE)
  if (!requireNamespace("purrr", quietly = TRUE)) stop("Package 'purrr' is required.", call. = FALSE)
  if (!requireNamespace("dplyr", quietly = TRUE)) stop("Package 'dplyr' is required.", call. = FALSE)
  if (!requireNamespace("tibble", quietly = TRUE)) stop("Package 'tibble' is required.", call. = FALSE)

  match_type <- match.arg(toupper(match_type), c("AND", "OR"))

  if (!is.character(search_term)) {
    stop("search_term must be a character string or vector of strings")
  }

  results <- purrr::map_dfr(seq_along(file_vector), function(idx) {
    file <- file_vector[idx]
    file_label <- if (!is.null(names(file_vector))) names(file_vector)[idx] else basename(file)
    ext <- tolower(tools::file_ext(file))

    if (ext == "parquet") {
      return(.search_parquet(file, file_label, search_term, match_type))
    }

    # SPSS (.sav) or Stata (.dta): read metadata only
    wave_data <- if (ext == "dta") {
      haven::read_dta(file, n_max = 0)
    } else {
      haven::read_sav(file, n_max = 0)
    }

    var_names <- names(wave_data)

    purrr::map_dfr(var_names, function(var) {
      label <- labelled::var_label(wave_data[[var]])
      label_text <- if (is.null(label)) "" else as.character(label)
      search_space <- paste(var, label_text)

      is_match <- if (match_type == "AND") {
        all(vapply(search_term, function(term) grepl(term, search_space, ignore.case = TRUE), logical(1)))
      } else {
        any(vapply(search_term, function(term) grepl(term, search_space, ignore.case = TRUE), logical(1)))
      }

      if (is_match) {
        val_labels <- labelled::val_labels(wave_data[[var]])
        values_list <- if (!is.null(val_labels)) {
          paste0(val_labels, " = ", names(val_labels))
        } else {
          "[No value labels]"
        }
        tibble::tibble(file = file_label, variable = var, label = label_text, values = list(values_list))
      } else {
        NULL
      }
    })
  })

  if (print_output && nrow(results) > 0) {
    cat("\n")
    cat(strrep("=", 60), "\n")
    cat("Search results for:", paste(search_term, collapse = paste0(" ", match_type, " ")), "\n")
    cat("Matches found:", nrow(results), "\n")
    cat(strrep("=", 60), "\n\n")

    for (i in seq_len(nrow(results))) {
      row <- results[i, ]
      cat("File:     ", row$file, "\n")
      cat("Variable: ", row$variable, "\n")
      cat("Label:    ", row$label, "\n")
      cat("Values:\n")
      for (v in row$values[[1]]) {
        cat("          ", v, "\n")
      }
      cat(strrep("-", 40), "\n")
    }
  }

  invisible(results)
}

# ---------------------------------------------------------------------------
# Internal: search a parquet file (no value labels in parquet, but column names
# and any stored metadata are searchable)
# ---------------------------------------------------------------------------

.search_parquet <- function(file, file_label, search_term, match_type) {
  if (!requireNamespace("arrow", quietly = TRUE)) stop("Package 'arrow' is required for parquet files.", call. = FALSE)

  schema <- arrow::open_dataset(file)$schema
  var_names <- names(schema)

  purrr::map_dfr(var_names, function(var) {
    # Parquet has no variable labels; search column name only
    search_space <- var

    is_match <- if (match_type == "AND") {
      all(vapply(search_term, function(term) grepl(term, search_space, ignore.case = TRUE), logical(1)))
    } else {
      any(vapply(search_term, function(term) grepl(term, search_space, ignore.case = TRUE), logical(1)))
    }

    if (is_match) {
      type_str <- schema$GetFieldByName(var)$type$ToString()
      tibble::tibble(
        file = file_label,
        variable = var,
        label = paste0("[parquet: ", type_str, "]"),
        values = list("[Parquet — no value labels]")
      )
    } else {
      NULL
    }
  })
}
