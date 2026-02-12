# src/r/codebook/codebook_workflow.R
# Integration functions connecting search → analyze → generate

# ==============================================================================
# MAIN WORKFLOW: Search Results → YAML
# ==============================================================================

#' Complete workflow: analyze search results and generate YAML template
#'
#' Takes output from extract_matches() and produces a ready-to-use YAML template
#' organized by question, with auto-detected scale types and reversals flagged.
#'
#' @param search_results Data frame from extract_matches() with columns:
#'   - wave: character ("w1", "w2", ...)
#'   - variable_name: character (original variable name)
#'   - variable_label: character (question text)
#'   - value_labels: list of named character vectors OR NULL
#'
#' @param concept Character: concept area for this analysis
#'   (e.g., "economy", "politics", "governance")
#'
#' @param save_to Character: if provided, save YAML to this file path.
#'   If NULL (default), return YAML as string.
#'
#' @return Character string with YAML (if save_to=NULL) or invisible(TRUE)
#'   if file was saved.
#'
#' @details
#' Workflow:
#' 1. Parse search results into structured format
#' 2. Group by question number (handles q1, q001, q01 variants)
#' 3. Detect scale types and reversals per wave
#' 4. Generate YAML with comments and auto-filled source mappings
#' 5. Save or return
#'
#' User then:
#' - Fills in `id` field with appropriate identifier
#' - Confirms or adjusts harmonization methods
#' - Adds QC bounds if needed
#' - Runs `/harmonize-variables` skill
#'
#' @examples
#' \\dontrun{
#' # From search results to YAML file
#' results <- extract_matches("economic condition", w1, w2, w3)
#' generate_codebook_yaml(results, concept = "economy", save_to = "economy.yml")
#'
#' # Or get YAML as string for review before saving
#' yaml_str <- generate_codebook_yaml(results, concept = "economy")
#' cat(yaml_str)
#' }
#'
#' @export
generate_codebook_yaml <- function(
  search_results,
  concept = "concept",
  save_to = NULL
) {

  # Step 1: Parse
  parsed <- parse_search_results(search_results)

  if (nrow(parsed) == 0) {
    warning("No results to process")
    return(if (is.null(save_to)) "" else invisible(FALSE))
  }

  # Step 2: Group by question
  grouped <- group_by_question(parsed)

  if (length(grouped) == 0) {
    warning("Could not identify any questions in results")
    return(if (is.null(save_to)) "" else invisible(FALSE))
  }

  # Step 3 & 4: Generate YAML
  yaml_text <- generate_yaml_template(grouped, concept = concept)

  # Step 5: Save or return
  if (!is.null(save_to)) {
    writeLines(yaml_text, save_to)
    cat(sprintf("✅ YAML template saved to: %s\n", save_to))
    return(invisible(TRUE))
  } else {
    return(yaml_text)
  }
}

# ==============================================================================
# ANALYSIS & REPORTING
# ==============================================================================

#' Generate detailed analysis report of search results
#'
#' Produces human-readable summary of scale types, reversals, and recommendations.
#'
#' @param search_results Data frame from extract_matches()
#' @param concept Character: concept area
#'
#' @return Character string with formatted report
#'
#' @export
analyze_search_results <- function(search_results, concept = "concept") {

  parsed <- parse_search_results(search_results)
  grouped <- group_by_question(parsed)

  lines <- character()

  lines <- c(lines, sprintf("# Analysis Report: %s\n", concept))
  lines <- c(lines, sprintf("Generated: %s\n", format(Sys.time(), "%Y-%m-%d %H:%M:%S")))

  lines <- c(lines, sprintf("## Summary\n"))
  lines <- c(lines, sprintf("- Total matches: %d", nrow(parsed)))
  lines <- c(lines, sprintf("- Waves represented: %s", paste(unique(parsed$wave), collapse = ", ")))
  lines <- c(lines, sprintf("- Questions identified: %s\n", paste(names(grouped), collapse = ", ")))

  # Per-question analysis
  lines <- c(lines, "## Question-by-Question Analysis\n")

  for (q_key in names(grouped)) {

    q_data <- grouped[[q_key]]
    lines <- c(lines, sprintf("### %s\n", toupper(q_key)))

    # First label
    first_label <- NA_character_
    for (w in names(q_data)) {
      if (!is.na(q_data[[w]]$label)) {
        first_label <- q_data[[w]]$label
        break
      }
    }

    if (!is.na(first_label)) {
      lines <- c(lines, sprintf("**Question:** %s\n", first_label))
    }

    # Waves and variables
    lines <- c(lines, "**Source variables:**")
    for (w in sort(names(q_data))) {
      var <- q_data[[w]]$var_name
      lines <- c(lines, sprintf("- %s: `%s`", w, var))
    }
    lines <- c(lines, "")

    # Scale analysis
    scale_info <- list()
    for (w in names(q_data)) {
      labels <- q_data[[w]]$value_labels
      scale_info[[w]] <- detect_scale_type(1:10, labels)
    }

    lines <- c(lines, "**Scale detection:**")
    for (w in sort(names(scale_info))) {
      info <- scale_info[[w]]
      if (!is.na(info$type)) {
        lines <- c(
          lines,
          sprintf(
            "- %s: %s scale, %s, %.0f%% confidence",
            w,
            info$type,
            info$direction,
            info$confidence * 100
          )
        )
      }
    }
    lines <- c(lines, "")

    # Reversals
    reversals <- detect_reversals(
      lapply(q_data, function(x) x$value_labels)
    )

    if (nrow(reversals$reversed_pairs) > 0) {
      lines <- c(lines, "**⚠️ REVERSALS DETECTED:**")
      for (i in 1:nrow(reversals$reversed_pairs)) {
        w1 <- reversals$reversed_pairs$wave_1[i]
        w2 <- reversals$reversed_pairs$wave_2[i]
        lines <- c(
          lines,
          sprintf(
            "- %s and %s have opposite semantic direction (consider `safe_reverse_*pt()`)",
            w1, w2
          )
        )
      }
      lines <- c(lines, "")
    }

    lines <- c(lines, "---\n")
  }

  # Recommendations
  lines <- c(lines, "## Recommendations\n")
  lines <- c(lines, "1. Review scale detection confidence - items < 70% may need manual verification")
  lines <- c(lines, "2. Confirm reversal flags - not all semantic differences indicate reversals")
  lines <- c(lines, "3. Fill in YAML template:")
  lines <- c(lines, "   - Set `id` field for each variable")
  lines <- c(lines, "   - Confirm `harmonize` method choices")
  lines <- c(lines, "   - Set QC `valid_range_by_wave` if needed")
  lines <- c(lines, "")

  paste(lines, collapse = "\n")
}

# ==============================================================================
# BATCH PROCESSING UTILITIES
# ==============================================================================

#' Process multiple search results into separate YAML files
#'
#' Useful for organizing YAML by concept domain.
#'
#' @param search_results_list Named list of search result data frames
#'   e.g. list(economy = results_econ, politics = results_politics)
#'
#' @param output_dir Character: directory to save YAML files
#'
#' @return Invisible data frame with file paths and status
#'
#' @details
#' Creates files: output_dir/economy.yml, output_dir/politics.yml, etc.
#'
#' @export
batch_generate_yaml <- function(search_results_list, output_dir = "src/config/harmonize") {

  # Create directory if needed
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  results_df <- data.frame(
    concept = character(),
    file_path = character(),
    n_matches = numeric(),
    status = character(),
    stringsAsFactors = FALSE
  )

  for (concept in names(search_results_list)) {

    search_results <- search_results_list[[concept]]
    file_path <- file.path(output_dir, sprintf("%s.yml", concept))

    tryCatch({
      generate_codebook_yaml(
        search_results,
        concept = concept,
        save_to = file_path
      )

      results_df <- rbind(
        results_df,
        data.frame(
          concept = concept,
          file_path = file_path,
          n_matches = nrow(search_results),
          status = "✅ OK",
          stringsAsFactors = FALSE
        )
      )

    }, error = function(e) {
      results_df <<- rbind(
        results_df,
        data.frame(
          concept = concept,
          file_path = file_path,
          n_matches = nrow(search_results),
          status = sprintf("❌ Error: %s", e$message),
          stringsAsFactors = FALSE
        )
      )
    })
  }

  print(results_df)
  invisible(results_df)
}

# ==============================================================================
# HELPER: Convert search results to data frame (if needed)
# ==============================================================================

#' Normalize search results to standard data frame format
#'
#' Handles various input formats from different search functions.
#'
#' @param search_results Input object (list, data frame, or other)
#'
#' @return Data frame with normalized columns
#'
#' @keywords internal
normalize_search_results <- function(search_results) {

  # Already a data frame?
  if (is.data.frame(search_results)) {
    return(search_results)
  }

  # List of lists?
  if (is.list(search_results) && all(sapply(search_results, is.list))) {
    return(do.call(rbind, lapply(search_results, as.data.frame)))
  }

  # Something else - try to coerce
  tryCatch({
    as.data.frame(search_results)
  }, error = function(e) {
    stop("Cannot convert search_results to data frame: ", e$message)
  })
}
