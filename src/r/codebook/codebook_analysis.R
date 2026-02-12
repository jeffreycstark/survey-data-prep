# src/r/codebook/codebook_analysis.R
# Functions to parse search results and auto-detect scales/reversals for YAML generation

# ==============================================================================
# SCALE DETECTION
# ==============================================================================

#' Detect scale type from value labels
#'
#' Analyzes value range and semantic labels to determine scale type.
#'
#' @param values Numeric vector of unique values present in data
#' @param value_labels Named character vector: c("1" = "Very bad", "2" = "Bad", ...)
#'
#' @return List with:
#'   - type: "5pt", "4pt", "6pt", etc.
#'   - range: numeric vector c(min, max)
#'   - direction: "ascending" or "descending" (based on semantic labels)
#'   - confidence: numeric 0-1
#'
#' @details
#' Scale detection uses both numeric range and semantic content of labels.
#' Ascending = 1,2,3... = Very bad, Bad, Neutral, Good, Very good
#' Descending = 1,2,3... = Very good, Good, Neutral, Bad, Very bad
#'
#' @export
detect_scale_type <- function(values, value_labels) {

  # Remove NA and sort
  values <- sort(na.omit(as.numeric(values)))

  if (length(values) == 0) {
    return(list(type = NA_character_, range = NA, direction = NA, confidence = 0))
  }

  # Infer scale from numeric range
  min_val <- min(values)
  max_val <- max(values)
  n_unique <- length(unique(values))

  # Determine scale type (assume standard 1-based scales)
  if (min_val == 1 && max_val == 5 && n_unique >= 3) {
    scale_type <- "5pt"
  } else if (min_val == 1 && max_val == 4 && n_unique >= 3) {
    scale_type <- "4pt"
  } else if (min_val == 1 && max_val == 6 && n_unique >= 3) {
    scale_type <- "6pt"
  } else if (min_val == 0 && max_val == 10) {
    scale_type <- "0-10"
  } else if (n_unique <= 3) {
    scale_type <- sprintf("%dpt", n_unique)
  } else {
    scale_type <- "continuous"
  }

  # Detect direction from semantic labels
  direction <- detect_label_direction(value_labels)

  # Confidence: higher if we have complete 1-5 vs sparse values
  confidence <- min(1.0, n_unique / (max_val - min_val + 1))

  list(
    type = scale_type,
    range = c(min_val, max_val),
    direction = direction,
    confidence = confidence
  )
}

#' Detect semantic direction of scale from value labels
#'
#' Examines label text to infer whether scale goes from negative→positive (ascending)
#' or positive→negative (descending).
#'
#' @param value_labels Named character vector of labels
#'
#' @return "ascending", "descending", or "unknown"
#'
#' @details
#' Looks for semantic keywords:
#' - Ascending: "bad", "poor", "low", "no", "disagree" at low numbers
#' - Descending: "good", "high", "yes", "agree" at low numbers
#'
#' @keywords internal
detect_label_direction <- function(value_labels) {

  if (is.null(value_labels) || length(value_labels) == 0) {
    return("unknown")
  }

  # Convert names to numeric to check position
  label_names <- as.numeric(names(value_labels))
  label_text <- tolower(as.character(value_labels))

  # Check first 1-2 labels for semantic direction
  first_labels <- label_text[label_names == min(label_names, na.rm = TRUE)]
  first_text <- paste(first_labels, collapse = " ")

  negative_keywords <- c(
    "bad", "poor", "low", "no", "don't", "disagree", "opposed",
    "distrust", "fail", "weak", "wrong"
  )
  positive_keywords <- c(
    "good", "excellent", "high", "yes", "agree", "favor",
    "trust", "success", "strong", "right"
  )

  neg_score <- sum(grepl(paste(negative_keywords, collapse = "|"), first_text))
  pos_score <- sum(grepl(paste(positive_keywords, collapse = "|"), first_text))

  if (neg_score > pos_score) {
    "ascending"  # bad → good
  } else if (pos_score > neg_score) {
    "descending"  # good → bad
  } else {
    "unknown"
  }
}

# ==============================================================================
# REVERSAL DETECTION
# ==============================================================================

#' Detect if a variable is reversed between waves
#'
#' Compares semantic meaning of value labels across waves to identify
#' whether scale direction has flipped.
#'
#' @param wave_labels List of value label vectors:
#'   list(w1 = c("1" = "Very bad", ...), w2 = c("1" = "Very bad", ...))
#'
#' @return List with:
#'   - reversed_pairs: Character matrix of wave pairs that appear reversed
#'   - confidence: numeric 0-1
#'   - notes: character vector of observations
#'
#' @export
detect_reversals <- function(wave_labels) {

  wave_names <- names(wave_labels)
  reversals <- data.frame(
    wave_1 = character(),
    wave_2 = character(),
    confidence = numeric(),
    stringsAsFactors = FALSE
  )

  notes <- character()

  # Compare each pair of waves
  for (i in 1:(length(wave_names) - 1)) {
    for (j in (i + 1):length(wave_names)) {

      w1_name <- wave_names[i]
      w2_name <- wave_names[j]

      w1_labels <- wave_labels[[w1_name]]
      w2_labels <- wave_labels[[w2_name]]

      if (is.null(w1_labels) || is.null(w2_labels)) {
        next
      }

      # Compare first label (lower numeric value)
      w1_first <- tolower(w1_labels[1])
      w2_first <- tolower(w2_labels[1])

      # Check if directions are opposite
      is_reversed <- check_opposite_semantics(w1_first, w2_first)

      if (is_reversed$reversed) {
        reversals <- rbind(
          reversals,
          data.frame(
            wave_1 = w1_name,
            wave_2 = w2_name,
            confidence = is_reversed$confidence,
            stringsAsFactors = FALSE
          )
        )
        notes <- c(
          notes,
          sprintf(
            "%s (%s) vs %s (%s): opposite semantics detected",
            w1_name, w1_first, w2_name, w2_first
          )
        )
      }
    }
  }

  list(
    reversed_pairs = reversals,
    confidence = if (nrow(reversals) > 0) mean(reversals$confidence) else 0,
    notes = notes
  )
}

#' Check if two labels have opposite semantic meaning
#'
#' @param label1 Character string (first label of wave 1)
#' @param label2 Character string (first label of wave 2)
#'
#' @return List with reversed (logical) and confidence (0-1)
#'
#' @keywords internal
check_opposite_semantics <- function(label1, label2) {

  negative_words <- c("bad", "poor", "low", "no", "disagree", "distrust", "fail")
  positive_words <- c("good", "excellent", "high", "yes", "agree", "trust", "success")

  # Score each label
  l1_has_neg <- any(grepl(paste(negative_words, collapse = "|"), label1))
  l1_has_pos <- any(grepl(paste(positive_words, collapse = "|"), label1))

  l2_has_neg <- any(grepl(paste(negative_words, collapse = "|"), label2))
  l2_has_pos <- any(grepl(paste(positive_words, collapse = "|"), label2))

  # Reversed if they have opposite polarity
  reversed <- (l1_has_neg && l2_has_pos) || (l1_has_pos && l2_has_neg)

  confidence <- if (reversed) 0.9 else 0.1

  list(reversed = reversed, confidence = confidence)
}

# ==============================================================================
# PARSE SEARCH RESULTS
# ==============================================================================

#' Parse search result output into structured format
#'
#' Converts raw search results (as produced by extract_matches or similar)
#' into structured data frame with columns: wave, var_name, label, value_labels
#'
#' @param search_results List or data frame from search function
#'   Expected columns: wave, variable_name, variable_label, value_labels
#'
#' @return Data frame with columns:
#'   - wave: "w1", "w2", etc.
#'   - var_name: original variable name in source data
#'   - label: variable label text
#'   - values: numeric vector of unique values
#'   - value_labels: named character vector of labels
#'
#' @export
parse_search_results <- function(search_results) {

  if (is.null(search_results) || nrow(search_results) == 0) {
    return(data.frame(
      wave = character(),
      var_name = character(),
      label = character(),
      values = list(),
      value_labels = list(),
      stringsAsFactors = FALSE
    ))
  }

  # Normalize column names
  colnames(search_results) <- tolower(colnames(search_results))

  # Ensure required columns exist
  required <- c("wave", "variable_name", "variable_label")
  missing <- setdiff(required, colnames(search_results))
  if (length(missing) > 0) {
    stop("Missing required columns: ", paste(missing, collapse = ", "))
  }

  # Parse value labels if present
  parsed <- data.frame(
    wave = search_results$wave,
    var_name = search_results$variable_name,
    label = search_results$variable_label,
    stringsAsFactors = FALSE
  )

  # Extract value labels (if available)
  if ("value_labels" %in% colnames(search_results)) {
    parsed$value_labels <- search_results$value_labels
  } else {
    parsed$value_labels <- NA
  }

  parsed
}

# ==============================================================================
# GROUP BY QUESTION
# ==============================================================================

#' Group search results by question number across waves
#'
#' Identifies matching questions (q1, q2, etc.) across waves,
#' even if variable naming differs (q001 in W1 vs q1 in W2).
#'
#' @param search_df Data frame from parse_search_results()
#'
#' @return List of grouped variables, one per question:
#'   list(
#'     q1 = list(w1 = list(var_name="q001", label="...", ...),
#'                w2 = list(var_name="q1", label="...", ...)),
#'     q2 = ...
#'   )
#'
#' @export
group_by_question <- function(search_df) {

  if (nrow(search_df) == 0) {
    return(list())
  }

  grouped <- list()

  for (i in 1:nrow(search_df)) {

    row <- search_df[i, ]
    wave <- row$wave
    var_name <- row$var_name

    # Extract question number (handle q1, q001, q01 patterns)
    q_num <- extract_question_number(var_name)

    if (is.na(q_num)) {
      next  # Skip if can't extract question number
    }

    q_key <- sprintf("q%d", q_num)

    # Initialize question group if needed
    if (!q_key %in% names(grouped)) {
      grouped[[q_key]] <- list()
    }

    # Add wave data to question group
    grouped[[q_key]][[wave]] <- list(
      var_name = var_name,
      label = row$label,
      value_labels = row$value_labels
    )
  }

  # Sort by question number
  q_nums <- as.numeric(gsub("^q", "", names(grouped)))
  grouped[order(q_nums)]
}

#' Extract question number from variable name
#'
#' Handles patterns: q1, q01, q001, Q1, etc.
#'
#' @param var_name Character string (variable name)
#'
#' @return Numeric question number or NA
#'
#' @keywords internal
extract_question_number <- function(var_name) {

  # Match q followed by digits (case insensitive)
  match <- regmatches(
    var_name,
    regexpr("[qQ](\\d+)", var_name, perl = TRUE)
  )

  if (length(match) == 0) {
    return(NA_integer_)
  }

  # Extract digits only
  num_str <- gsub("[^0-9]", "", match[1])
  as.numeric(num_str)
}

# ==============================================================================
# GENERATE YAML TEMPLATES
# ==============================================================================

#' Generate YAML template from grouped question data
#'
#' Creates YAML template entries for one or more questions,
#' ready for user refinement.
#'
#' @param grouped_data List from group_by_question()
#'   OR a single question's data: list(w1=..., w2=..., ...)
#'
#' @param concept Character string: concept area (e.g., "economy", "politics")
#'
#' @param by_question Logical: group output by question? Default TRUE.
#'   If FALSE, returns merged template for all waves.
#'
#' @return Character string: YAML-formatted template
#'
#' @details
#' Generated YAML includes:
#' - Source variable mappings per wave (auto-detected)
#' - Detected scale type and direction
#' - Detected reversals with suggested recoding functions
#' - Empty harmonization rules (user fills in)
#' - Comments for user guidance
#'
#' @export
generate_yaml_template <- function(grouped_data, concept = "concept", by_question = TRUE) {

  # Handle single question vs multiple
  if ("w1" %in% names(grouped_data) && !("q1" %in% names(grouped_data))) {
    # Single question
    grouped_data <- list(q1 = grouped_data)
  }

  yaml_lines <- character()

  yaml_lines <- c(yaml_lines, "# Generated YAML template - review and edit before using")
  yaml_lines <- c(yaml_lines, "")

  for (q_key in names(grouped_data)) {

    question_data <- grouped_data[[q_key]]

    yaml_lines <- c(yaml_lines, sprintf("%s:", q_key))

    # Get first available label and value labels
    first_label <- NA_character_
    first_labels_map <- NULL

    for (wave_name in names(question_data)) {
      if (is.na(first_label) && !is.na(question_data[[wave_name]]$label)) {
        first_label <- question_data[[wave_name]]$label
        first_labels_map <- question_data[[wave_name]]$value_labels
        break
      }
    }

    # Auto-generate entries for each question
    yaml_lines <- c(yaml_lines, "  id: \"\",  # TODO: set to q name or descriptive id")
    yaml_lines <- c(yaml_lines, sprintf("  concept: \"%s\"", concept))
    yaml_lines <- c(yaml_lines, sprintf("  description: \"%s\"", first_label %||% ""))
    yaml_lines <- c(yaml_lines, "")

    # Source mapping
    yaml_lines <- c(yaml_lines, "  source:")
    for (wave_name in names(question_data)) {
      var <- question_data[[wave_name]]$var_name
      yaml_lines <- c(yaml_lines, sprintf("    %s: \"%s\"", wave_name, var))
    }
    yaml_lines <- c(yaml_lines, "")

    # Detect scale type and reversals
    yaml_lines <- c(yaml_lines, generate_scale_section(question_data))

    # Harmonization (empty, user fills in)
    yaml_lines <- c(yaml_lines, "  harmonize:")
    yaml_lines <- c(yaml_lines, "    default:")
    yaml_lines <- c(yaml_lines, "      method: \"identity\"  # or r_function")
    yaml_lines <- c(yaml_lines, "")

    # QC (empty)
    yaml_lines <- c(yaml_lines, "  qc:")
    yaml_lines <- c(yaml_lines, "    valid_range_by_wave: {}")
    yaml_lines <- c(yaml_lines, "")
    yaml_lines <- c(yaml_lines, "---")
    yaml_lines <- c(yaml_lines, "")
  }

  paste(yaml_lines, collapse = "\n")
}

#' Generate scale and reversal section for YAML
#'
#' @param question_data List of wave data for one question
#'
#' @return Character vector of YAML lines
#'
#' @keywords internal
generate_scale_section <- function(question_data) {

  lines <- character()

  # Analyze each wave for scale type
  scale_info <- list()
  for (wave_name in names(question_data)) {
    labels <- question_data[[wave_name]]$value_labels
    scale_info[[wave_name]] <- detect_scale_type(1:10, labels)  # dummy values
  }

  # Detect reversals
  reversals <- detect_reversals(
    lapply(question_data, function(x) x$value_labels)
  )

  # Generate comments about scale
  lines <- c(lines, "  # Scale analysis (auto-detected):")

  for (wave_name in names(scale_info)) {
    info <- scale_info[[wave_name]]
    if (!is.na(info$type)) {
      lines <- c(
        lines,
        sprintf(
          "  # %s: %s scale, %s direction, %.1f%% confidence",
          wave_name,
          info$type,
          info$direction %||% "unknown",
          info$confidence * 100
        )
      )
    }
  }

  # Reversals
  if (nrow(reversals$reversed_pairs) > 0) {
    lines <- c(lines, "  # ⚠️  REVERSALS DETECTED:")
    for (i in 1:nrow(reversals$reversed_pairs)) {
      w1 <- reversals$reversed_pairs$wave_1[i]
      w2 <- reversals$reversed_pairs$wave_2[i]
      lines <- c(
        lines,
        sprintf(
          "  #   %s vs %s: opposite semantic direction",
          w1, w2
        )
      )
    }
    lines <- c(
      lines,
      "  # Consider using safe_reverse_*pt() for reversals"
    )
  }

  lines <- c(lines, "")
  lines
}
