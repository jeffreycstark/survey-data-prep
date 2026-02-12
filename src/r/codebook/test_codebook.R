# src/r/codebook/test_codebook.R
# Test cases for codebook analysis and YAML generation

library(testthat)

# ==============================================================================
# TEST SUITE 1: SCALE DETECTION
# ==============================================================================

test_that("detect_scale_type: 5-point scale", {
  values <- c(1, 2, 3, 4, 5)
  labels <- c("1" = "Very bad", "2" = "Bad", "3" = "Neutral", "4" = "Good", "5" = "Very good")

  result <- detect_scale_type(values, labels)

  expect_equal(result$type, "5pt")
  expect_equal(result$range, c(1, 5))
  expect_equal(result$direction, "ascending")
  expect_gt(result$confidence, 0.7)
})

test_that("detect_scale_type: 4-point scale", {
  values <- c(1, 2, 3, 4)
  labels <- c("1" = "Strongly disagree", "2" = "Disagree", "3" = "Agree", "4" = "Strongly agree")

  result <- detect_scale_type(values, labels)

  expect_equal(result$type, "4pt")
  expect_equal(result$range, c(1, 4))
})

test_that("detect_scale_type: 6-point scale", {
  values <- 1:6
  labels <- c("1" = "Very bad", "2" = "Bad", "3" = "Poor", "4" = "Fair", "5" = "Good", "6" = "Very good")

  result <- detect_scale_type(values, labels)

  expect_equal(result$type, "6pt")
  expect_equal(result$range, c(1, 6))
})

test_that("detect_scale_type: empty input", {
  result <- detect_scale_type(NA, NULL)

  expect_true(is.na(result$type))
  expect_equal(result$confidence, 0)
})

# ==============================================================================
# TEST SUITE 2: REVERSAL DETECTION
# ==============================================================================

test_that("detect_label_direction: ascending (bad → good)", {
  labels <- c("1" = "Very bad", "2" = "Bad", "3" = "Neutral", "4" = "Good", "5" = "Very good")

  result <- detect_label_direction(labels)

  expect_equal(result, "ascending")
})

test_that("detect_label_direction: descending (good → bad)", {
  labels <- c("1" = "Very good", "2" = "Good", "3" = "Neutral", "4" = "Bad", "5" = "Very bad")

  result <- detect_label_direction(labels)

  expect_equal(result, "descending")
})

test_that("check_opposite_semantics: detects reversal", {
  result <- check_opposite_semantics("Very bad", "Very good")

  expect_true(result$reversed)
  expect_gt(result$confidence, 0.8)
})

test_that("check_opposite_semantics: no reversal", {
  result <- check_opposite_semantics("Very bad", "Somewhat bad")

  expect_false(result$reversed)
})

test_that("detect_reversals: identifies flipped scales", {
  wave_labels <- list(
    w1 = c("1" = "Very bad", "2" = "Bad", "3" = "Good", "4" = "Very good"),
    w2 = c("1" = "Very good", "2" = "Good", "3" = "Bad", "4" = "Very bad")
  )

  result <- detect_reversals(wave_labels)

  expect_gt(nrow(result$reversed_pairs), 0)
  expect_equal(result$reversed_pairs$wave_1[1], "w1")
  expect_equal(result$reversed_pairs$wave_2[1], "w2")
})

# ==============================================================================
# TEST SUITE 3: QUESTION NUMBER EXTRACTION
# ==============================================================================

test_that("extract_question_number: q1 pattern", {
  expect_equal(extract_question_number("q1"), 1)
})

test_that("extract_question_number: q001 pattern", {
  expect_equal(extract_question_number("q001"), 1)
})

test_that("extract_question_number: q01 pattern", {
  expect_equal(extract_question_number("q01"), 1)
})

test_that("extract_question_number: Q5 (uppercase)", {
  expect_equal(extract_question_number("Q5"), 5)
})

test_that("extract_question_number: no match", {
  expect_true(is.na(extract_question_number("var123")))
})

# ==============================================================================
# TEST SUITE 4: GROUPING BY QUESTION
# ==============================================================================

test_that("group_by_question: basic grouping", {
  search_df <- data.frame(
    wave = c("w1", "w2", "w1", "w2"),
    var_name = c("q001", "q1", "q002", "q2"),
    label = c("Question 1", "Question 1", "Question 2", "Question 2"),
    value_labels = list(NA, NA, NA, NA),
    stringsAsFactors = FALSE
  )

  result <- group_by_question(search_df)

  expect_equal(length(result), 2)
  expect_true("q1" %in% names(result))
  expect_true("q2" %in% names(result))
  expect_equal(length(result$q1), 2)  # w1 and w2
})

test_that("group_by_question: handles missing questions", {
  search_df <- data.frame(
    wave = c("w1", "w1"),
    var_name = c("q1", "q5"),
    label = c("Q1", "Q5"),
    value_labels = list(NA, NA),
    stringsAsFactors = FALSE
  )

  result <- group_by_question(search_df)

  expect_equal(length(result), 2)
  expect_equal(names(result), c("q1", "q5"))
})

# ==============================================================================
# TEST SUITE 5: YAML GENERATION
# ==============================================================================

test_that("generate_yaml_template: produces valid structure", {
  q_data <- list(
    w1 = list(
      var_name = "q1",
      label = "Overall economic condition",
      value_labels = c("1" = "Very bad", "5" = "Very good")
    ),
    w2 = list(
      var_name = "q1",
      label = "Overall economic condition",
      value_labels = c("1" = "Very bad", "5" = "Very good")
    )
  )

  grouped <- list(q1 = q_data)
  yaml_str <- generate_yaml_template(grouped, concept = "economy")

  expect_true(grepl("q1:", yaml_str))
  expect_true(grepl("w1:", yaml_str))
  expect_true(grepl("w2:", yaml_str))
  expect_true(grepl("source:", yaml_str))
  expect_true(grepl("harmonize:", yaml_str))
})

# ==============================================================================
# TEST SUITE 6: PARSE SEARCH RESULTS
# ==============================================================================

test_that("parse_search_results: basic parsing", {
  search_df <- data.frame(
    Wave = c("w1", "w2"),
    Variable_Name = c("q001", "q1"),
    Variable_Label = c("Q1", "Q1"),
    Value_Labels = list(
      c("1" = "Bad", "5" = "Good"),
      c("1" = "Bad", "5" = "Good")
    ),
    stringsAsFactors = FALSE
  )

  result <- parse_search_results(search_df)

  expect_equal(nrow(result), 2)
  expect_equal(colnames(result)[1], "wave")
  expect_equal(result$var_name[1], "q001")
})

test_that("parse_search_results: missing columns error", {
  search_df <- data.frame(
    Wave = c("w1", "w2"),
    stringsAsFactors = FALSE
  )

  expect_error(parse_search_results(search_df))
})

# ==============================================================================
# TEST SUITE 7: WORKFLOW INTEGRATION
# ==============================================================================

test_that("generate_codebook_yaml: end-to-end", {
  search_df <- data.frame(
    wave = c("w1", "w2", "w3"),
    variable_name = c("q001", "q1", "q1"),
    variable_label = c(
      "Overall national economy",
      "Overall national economy",
      "Overall national economy"
    ),
    value_labels = list(
      c("1" = "Very bad", "2" = "Bad", "3" = "Good", "4" = "Very good"),
      c("1" = "Very bad", "2" = "Bad", "3" = "Good", "4" = "Very good"),
      c("1" = "Very good", "2" = "Good", "3" = "Bad", "4" = "Very bad")
    ),
    stringsAsFactors = FALSE
  )

  yaml_str <- generate_codebook_yaml(search_df, concept = "economy")

  expect_true(is.character(yaml_str))
  expect_true(grepl("q1:", yaml_str))
  expect_true(grepl("source:", yaml_str))
  expect_true(grepl("REVERSAL", yaml_str))  # w3 has reversed scale
})

test_that("generate_codebook_yaml: saves to file", {
  search_df <- data.frame(
    wave = c("w1", "w2"),
    variable_name = c("q1", "q1"),
    variable_label = c("Q1", "Q1"),
    value_labels = list(NA, NA),
    stringsAsFactors = FALSE
  )

  temp_file <- tempfile(fileext = ".yml")

  result <- generate_codebook_yaml(search_df, concept = "test", save_to = temp_file)

  expect_true(file.exists(temp_file))
  expect_true(result)  # invisible(TRUE)

  file.remove(temp_file)
})

# ==============================================================================
# TEST SUITE 8: ANALYZE SEARCH RESULTS
# ==============================================================================

test_that("analyze_search_results: produces report", {
  search_df <- data.frame(
    wave = c("w1", "w2"),
    variable_name = c("q1", "q1"),
    variable_label = c("Economy", "Economy"),
    value_labels = list(NA, NA),
    stringsAsFactors = FALSE
  )

  report <- analyze_search_results(search_df, concept = "economy")

  expect_true(is.character(report))
  expect_true(grepl("Analysis Report", report))
  expect_true(grepl("economy", report, ignore.case = TRUE))
})
