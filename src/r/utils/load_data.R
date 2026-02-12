#' Load data from project data directory
#' 
#' @param filename Character. Name of the file to load
#' @param data_type Character. Type of data: "raw", "interim", or "processed"
#' @return Data frame or tibble
#' @export
#' @examples
#' df <- load_data("survey_data.rds", "processed")
load_data <- function(filename, data_type = "processed") {
  
  require(here)
  require(tidyverse)
  
  # Construct file path
  data_path <- here::here("data", data_type, filename)
  
  # Check if file exists
  if (!file.exists(data_path)) {
    stop("Data file not found: ", data_path)
  }
  
  # Detect file type and load accordingly
  ext <- tools::file_ext(filename)
  
  data <- switch(
    tolower(ext),
    "csv" = readr::read_csv(data_path, show_col_types = FALSE),
    "tsv" = readr::read_tsv(data_path, show_col_types = FALSE),
    "rds" = readRDS(data_path),
    "rda" = load(data_path),
    "rdata" = load(data_path),
    "dta" = haven::read_dta(data_path),
    "sav" = haven::read_sav(data_path),
    "xlsx" = readxl::read_excel(data_path),
    "xls" = readxl::read_excel(data_path),
    stop("Unsupported file type: ", ext)
  )
  
  message("Loaded data from: ", data_path)
  return(data)
}

#' Save data to project data directory
#' 
#' @param data Data frame or tibble to save
#' @param filename Character. Name of the file to save
#' @param data_type Character. Type of data: "interim" or "processed"
#' @export
save_data <- function(data, filename, data_type = "processed") {
  
  require(here)
  require(tidyverse)
  
  # Construct file path
  data_path <- here::here("data", data_type, filename)
  
  # Create directory if it doesn't exist
  dir.create(dirname(data_path), recursive = TRUE, showWarnings = FALSE)
  
  # Detect file type and save accordingly
  ext <- tools::file_ext(filename)
  
  switch(
    tolower(ext),
    "csv" = readr::write_csv(data, data_path),
    "tsv" = readr::write_tsv(data, data_path),
    "rds" = saveRDS(data, data_path),
    "rdata" = save(data, file = data_path),
    stop("Unsupported file type: ", ext)
  )
  
  message("Data saved to: ", data_path)
  invisible(data_path)
}


#' Load survey waves 1-6 for codebook analysis
#' 
#' Loads all 6 survey waves from .sav files for cross-wave variable analysis.
#' Waves 1-5: data/raw/wave{n}/ (auto-detects .sav file)
#' Wave 6: data/raw/wave6/W6_Cambodia_Release_20240819.sav
#' 
#' @return Named list with w1, w2, w3, w4, w5, w6 data frames
#' @details
#' For data harmonization analysis only. When producing final harmonized output,
#' use data/processed/w6_all_countries_merged.rds for wave 6.
#' @examples
#' waves <- load_survey_waves()
#' results <- extract_matches("trust", waves$w1, waves$w2, waves$w3, waves$w4, waves$w5, waves$w6)
#' @export
load_survey_waves <- function() {
  
  require(here)
  require(haven)
  
  cat("\n=== Loading Survey Waves for Codebook Analysis ===\n")
  
  # Waves 1-5: Auto-detect .sav file in wave directory
  waves <- list()
  
  for (wave_num in 1:5) {
    wave_dir <- here::here("data", "raw", paste0("wave", wave_num))
    
    # Find .sav file in wave directory
    sav_files <- list.files(wave_dir, pattern = "\\.sav$", ignore.case = TRUE)
    
    if (length(sav_files) == 0) {
      stop("No .sav file found in ", wave_dir)
    }
    
    if (length(sav_files) > 1) {
      warning("Multiple .sav files in ", wave_dir, ". Using: ", sav_files[1])
    }
    
    file_path <- file.path(wave_dir, sav_files[1])
    cat(paste0("Loading Wave ", wave_num, ": ", basename(file_path), "\n"))
    
    waves[[paste0("w", wave_num)]] <- haven::read_sav(file_path)
  }
  
  # Wave 6: Specific file (Cambodia only for codebook analysis)
  wave6_path <- here::here("data", "raw", "wave6", "W6_Cambodia_Release_20240819.sav")
  
  if (!file.exists(wave6_path)) {
    stop("Wave 6 file not found: ", wave6_path)
  }
  
  cat("Loading Wave 6: W6_Cambodia_Release_20240819.sav\n")
  waves$w6 <- haven::read_sav(wave6_path)
  
  # Print summary
  cat("\n=== Waves Loaded Successfully ===\n")
  for (w in names(waves)) {
    cat(sprintf("%s: %d rows × %d columns\n", toupper(w), nrow(waves[[w]]), ncol(waves[[w]])))
  }
  cat("Note: For final harmonization output, use data/processed/w6_all_countries_merged.rds\n\n")
  
  return(waves)
}

#' Extract variables matching keyword across survey waves
#' 
#' Searches variable labels and names for keyword match across all waves.
#' Returns data frame ready for codebook YAML generation.
#' 
#' @param keywords Character vector of keywords to search for
#' @param ... Data frames (waves) to search. Can pass as: w1, w2, w3, w4, w5, w6
#'            or as list(w1, w2, w3, w4, w5, w6)
#' 
#' @return Data frame with columns:
#'   - wave: character ("w1", "w2", ...)
#'   - variable_name: original variable name
#'   - variable_label: variable label/question text
#'   - value_labels: list of named character vectors for value labels
#' 
#' @details
#' Keyword search is case-insensitive and matches:
#' - Variable labels (question text)
#' - Variable names (for codes like "trust_govt")
#' 
#' @examples
#' waves <- load_survey_waves()
#' results <- extract_matches(c("trust"), waves$w1, waves$w2, waves$w3, waves$w4, waves$w5, waves$w6)
#' 
#' @export
extract_matches <- function(keywords, ...) {
  
  require(haven)
  require(stringr)
  require(dplyr)
  
  # Get all wave data from arguments
  args <- list(...)
  
  # If first arg is a list of data frames, use that
  if (length(args) == 1 && is.list(args[[1]]) && 
      all(sapply(args[[1]], is.data.frame))) {
    waves_list <- args[[1]]
  } else {
    # Otherwise, use the individual data frame arguments
    waves_list <- args
  }
  
  # Name the waves if not already named
  wave_names <- names(waves_list)
  if (is.null(wave_names)) {
    wave_names <- paste0("w", seq_along(waves_list))
  }
  
  # Initialize results
  all_results <- data.frame(
    wave = character(),
    variable_name = character(),
    variable_label = character(),
    value_labels = list(),
    stringsAsFactors = FALSE
  )
  
  # Search each wave
  for (wave_idx in seq_along(waves_list)) {
    
    wave_data <- waves_list[[wave_idx]]
    wave_name <- wave_names[wave_idx]
    
    # Get variable labels and names
    var_labels <- attr(wave_data, "variable.labels")
    if (is.null(var_labels)) {
      var_labels <- setNames(names(wave_data), names(wave_data))
    }
    
    var_names <- names(wave_data)
    
    # Search for keyword matches
    for (var_idx in seq_along(var_names)) {
      
      var_name <- var_names[var_idx]
      var_label <- var_labels[[var_name]] %||% var_name
      
      # Check if any keyword matches (case-insensitive)
      matches <- any(
        stringr::str_detect(
          stringr::str_to_lower(c(var_name, var_label)),
          stringr::str_to_lower(paste(keywords, collapse = "|"))
        )
      )
      
      if (matches) {
        
        # Extract value labels
        var_data <- wave_data[[var_name]]
        val_labels <- attr(var_data, "labels")
        
        if (!is.null(val_labels)) {
          # Convert to named character vector
          val_labels_chr <- as.character(names(val_labels))
          names(val_labels_chr) <- as.character(val_labels)
        } else {
          val_labels_chr <- NULL
        }
        
        # Add to results
        all_results <- rbind(
          all_results,
          data.frame(
            wave = wave_name,
            variable_name = var_name,
            variable_label = as.character(var_label),
            value_labels = list(val_labels_chr),
            stringsAsFactors = FALSE
          )
        )
      }
    }
  }
  
  # Print summary
  if (nrow(all_results) > 0) {
    cat(sprintf("\n✅ Found %d matching variables\n", nrow(all_results)))
    cat(sprintf("Keywords: %s\n", paste(keywords, collapse = ", ")))
    cat(sprintf("Waves: %s\n\n", paste(unique(all_results$wave), collapse = ", ")))
  } else {
    cat("No matches found\n")
  }
  
  return(all_results)
}

#' Extract institutional trust variables by question range
#' 
#' Extracts variables q7-q20 (institutional trust items) from each wave.
#' The labels contain institution names (parliament, government, media, courts, etc.).
#' 
#' @param ... Data frames (waves) to extract from. Can pass as: w1, w2, w3, w4, w5, w6
#'            or as list(w1, w2, w3, w4, w5, w6)
#' @param q_min Integer: minimum question number (default 7)
#' @param q_max Integer: maximum question number (default 20)
#' 
#' @return Data frame with columns:
#'   - wave: character ("w1", "w2", ...)
#'   - variable_name: original variable name (q7, q001, Q7, etc.)
#'   - variable_label: institution name / question text
#'   - value_labels: list of named character vectors for value labels
#' 
#' @details
#' Matches question patterns:
#' - q7, q007, q07, Q7, Q007, Q07
#' - Returns in same format as extract_matches() for YAML generation
#' 
#' @examples
#' waves <- load_survey_waves()
#' inst_results <- extract_institutional_trust(waves$w1, waves$w2, waves$w3, 
#'                                              waves$w4, waves$w5, waves$w6)
#' 
#' @export
extract_institutional_trust <- function(..., q_min = 7, q_max = 20) {
  
  require(haven)
  require(stringr)
  
  # Get all wave data from arguments
  args <- list(...)
  
  # If first arg is a list of data frames, use that
  if (length(args) == 1 && is.list(args[[1]]) && 
      all(sapply(args[[1]], is.data.frame))) {
    waves_list <- args[[1]]
  } else {
    # Otherwise, use the individual data frame arguments
    waves_list <- args
  }
  
  # Name the waves if not already named
  wave_names <- names(waves_list)
  if (is.null(wave_names)) {
    wave_names <- paste0("w", seq_along(waves_list))
  }
  
  # Collect results in a list (avoid rbind issues with list columns)
  results_list <- list()
  
  # Extract from each wave
  for (wave_idx in seq_along(waves_list)) {
    
    wave_data <- waves_list[[wave_idx]]
    wave_name <- wave_names[wave_idx]
    
    var_names <- names(wave_data)
    
    # Find variables matching q7-q20 pattern
    for (var_idx in seq_along(var_names)) {
      
      var_name <- var_names[var_idx]
      
      # Extract question number from variable name (handle q7, q007, q07, Q7, etc.)
      q_match <- stringr::str_extract(tolower(var_name), "q\\d+")
      
      if (!is.na(q_match)) {
        q_num <- as.numeric(stringr::str_extract(q_match, "\\d+"))
        
        # Check if in range q_min to q_max
        if (!is.na(q_num) && q_num >= q_min && q_num <= q_max) {
          
          # For haven-imported SPSS data, labels are in attr(column, "label")
          var_label <- attr(wave_data[[var_name]], "label") %||% var_name
          
          # Extract value labels
          var_data <- wave_data[[var_name]]
          val_labels <- attr(var_data, "labels")
          
          if (!is.null(val_labels)) {
            # Convert to named character vector
            val_labels_chr <- as.character(names(val_labels))
            names(val_labels_chr) <- as.character(val_labels)
          } else {
            val_labels_chr <- NULL
          }
          
          # Add to results list
          results_list[[length(results_list) + 1]] <- list(
            wave = wave_name,
            variable_name = var_name,
            variable_label = as.character(var_label),
            value_labels = val_labels_chr
          )
        }
      }
    }
  }
  
  # Convert list to data frame
  if (length(results_list) > 0) {
    all_results <- data.frame(
      wave = sapply(results_list, function(x) x$wave),
      variable_name = sapply(results_list, function(x) x$variable_name),
      variable_label = sapply(results_list, function(x) x$variable_label),
      stringsAsFactors = FALSE
    )
    # Add value_labels as list column
    all_results$value_labels <- lapply(results_list, function(x) x$value_labels)
  } else {
    all_results <- data.frame(
      wave = character(),
      variable_name = character(),
      variable_label = character(),
      value_labels = list(),
      stringsAsFactors = FALSE
    )
  }
  
  # Print summary
  if (nrow(all_results) > 0) {
    cat(sprintf("\n✅ Extracted %d institutional trust variables\n", nrow(all_results)))
    cat(sprintf("Question range: q%d - q%d\n", q_min, q_max))
    cat(sprintf("Waves: %s\n\n", paste(unique(all_results$wave), collapse = ", ")))
  } else {
    cat(sprintf("No variables found in range q%d - q%d\n", q_min, q_max))
  }
  
  return(all_results)
}
