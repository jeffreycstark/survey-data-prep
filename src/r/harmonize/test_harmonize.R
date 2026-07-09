# src/r/harmonize/test_harmonize.R
# Unit tests for harmonization functions

library(testthat)
library(yaml)
library(dplyr)

# The functions under test. Until 2026-07-09 this file sourced nothing, so a
# standalone `Rscript src/r/harmonize/test_harmonize.R` aborted with
# "could not find function harmonize_variable" and the suite never ran.
suppressMessages(source(here::here("src", "r", "harmonize", "_load_harmonize.R")))
source(here::here("src", "r", "utils", "recoding.R"))

# Mock data for testing
create_test_waves <- function() {
  set.seed(42)
  
  list(
    w1 = data.frame(
      id = 1:10,
      q001 = c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5),
      q002 = c(1, 2, 3, 4, 5, -1, 2, 3, 4, 5),
      check.names = FALSE
    ),
    w2 = data.frame(
      id = 1:10,
      q1 = c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5),
      q2 = c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5),
      check.names = FALSE
    ),
    w3 = data.frame(
      id = 1:10,
      q1 = c(5, 4, 3, 2, 1, 5, 4, 3, 2, 1),  # Need reversal
      q2 = c(5, 4, 3, 2, 1, -1, 4, 3, 2, 1),
      check.names = FALSE
    )
  )
}

# Add labels to test waves (for semantic validation)
add_labels_to_waves <- function(waves) {
  
  waves$w1$q001 <- structure(
    waves$w1$q001,
    label = "Overall national economic condition today"
  )
  
  waves$w3$q1 <- structure(
    waves$w3$q1,
    label = "Overall national economic condition today (reversed)"
  )
  
  waves
}

# ==============================================================================
# Test: Basic harmonization identity (no transformation)
# ==============================================================================

test_that("identity harmonization preserves values", {
  
  waves <- create_test_waves()
  
  var_spec <- list(
    id = "test_var",
    source = list(w1 = "q001", w2 = "q1"),
    missing = list(use_convention = "treat_as_na"),
    harmonize = list(
      default = list(method = "identity")
    ),
    qc = list()
  )
  
  missing_conventions <- list(treat_as_na = c(-1, 0, 7, 8, 9))
  
  result <- harmonize_variable(var_spec, waves, missing_conventions)
  
  expect_equal(length(result), 3)
  expect_equal(as.numeric(result$w1), c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5))
  expect_equal(as.numeric(result$w2), c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5))
})

# ==============================================================================
# Test: Missing code handling
# ==============================================================================

test_that("missing codes converted to NA", {
  
  waves <- create_test_waves()
  
  var_spec <- list(
    id = "test_missing",
    source = list(w1 = "q002", w2 = "q2"),
    missing = list(use_convention = "treat_as_na"),
    harmonize = list(
      default = list(method = "identity")
    ),
    qc = list()
  )
  
  missing_conventions <- list(treat_as_na = c(-1, 0, 7, 8, 9))
  
  result <- harmonize_variable(var_spec, waves, missing_conventions)
  
  # w1 has -1 in position 6, should become NA
  expect_true(is.na(result$w1[6]))
  expect_equal(as.numeric(result$w1[c(1, 2, 3, 4, 5)]), c(1, 2, 3, 4, 5))
})

# ==============================================================================
# Test: Missing source variable
# ==============================================================================

test_that("missing source variable returns all NA", {
  
  waves <- create_test_waves()
  
  var_spec <- list(
    id = "test_missing_src",
    source = list(w1 = "nonexistent", w2 = "q1"),
    missing = list(use_convention = "treat_as_na"),
    harmonize = list(
      default = list(method = "identity")
    ),
    qc = list()
  )
  
  missing_conventions <- list(treat_as_na = c(-1, 0, 7, 8, 9))
  
  result <- harmonize_variable(var_spec, waves, missing_conventions)
  
  # w1 source doesn't exist - should be all NA
  expect_true(all(is.na(result$w1)))
  # w2 source exists
  expect_equal(as.numeric(result$w2), c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5))
})

# ==============================================================================
# Test: Specification validation
# ==============================================================================

test_that("validate_harmonize_spec catches missing required fields", {

  # The validator is now a jsonvalidate wrapper around
  # src/config/_schema/harmonize_v1.schema.json (audit ticket B3), so it reports
  # JSON-path errors rather than the old imperative strings ("variables list").
  # Expectations updated 2026-07-09 when this suite was revived.

  # Missing `variables` entirely
  bad_spec1 <- list(
    schema_version = 1,
    missing_conventions = list(treat_as_na = c(-1, 0))
  )

  expect_error(
    validate_harmonize_spec(bad_spec1),
    "must have required property 'variables'"
  )

  # `variables` present and well-shaped, but a variable is missing `concept`
  bad_spec2 <- list(
    schema_version = 1,
    missing_conventions = list(treat_as_na = c(-1, 0)),
    variables = list(
      list(
        id = "var1",
        description = "desc",
        type = "ordinal",
        source = list(w1 = "q1"),
        missing = list(use_convention = "treat_as_na"),
        harmonize = list(default = list(method = "identity"))
        # concept missing
      )
    )
  )

  expect_error(
    validate_harmonize_spec(bad_spec2),
    "concept"
  )
})

test_that("validate_harmonize_spec validates type field", {

  bad_spec <- list(
    schema_version = 1,
    missing_conventions = list(treat_as_na = c(-1, 0)),
    variables = list(
      list(
        id = "var1",
        concept = "test",
        description = "desc",
        type = "invalid_type",  # Not ordinal/nominal/continuous
        source = list(w1 = "q1"),
        missing = list(use_convention = "treat_as_na"),
        harmonize = list(default = list(method = "identity"))
      )
    )
  )

  # Schema enforces an enum on `type`; jsonvalidate reports the allowed-values
  # violation at /variables/0/type rather than the old "Invalid type" string.
  expect_error(
    validate_harmonize_spec(bad_spec),
    "type"
  )
})

# ==============================================================================
# Test: Harmonization report
# ==============================================================================

test_that("report_harmonization generates summary statistics", {
  
  harmonized <- list(
    w1 = c(1, 2, 3, 4, 5, NA, 2, 3, 4, 5),
    w2 = c(1, 2, 3, 4, 5, 1, 2, 3, 4, 5)
  )
  
  var_spec <- list(id = "test_var")
  
  # Suppress printing
  result <- suppressMessages(
    report_harmonization(harmonized, var_spec, return_tbl = TRUE)
  )
  
  expect_equal(nrow(result), 2)
  expect_equal(result$n_missing[1], 1)
  expect_equal(result$n_missing[2], 0)
})

# ==============================================================================
# Run tests
# ==============================================================================

if (interactive()) {
  test_file(here::here("src/r/harmonize/test_harmonize.R"))
}
