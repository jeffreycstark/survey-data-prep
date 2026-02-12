#' Test script for identity (none) recoding functions
#'
#' Verifies that safe_3pt_none, safe_4pt_none, and safe_5pt_none
#' correctly handle missing codes without reversing values

# Load required packages
library(dplyr)

# Source the recoding functions
source(here::here("R/utils/recoding.R"))

cat("=== Testing Identity Recoding Functions ===\n\n")

# Test data with valid values and missing codes
test_3pt <- c(1, 2, 3, -1, 0, 7, 8, 9, NA, 1, 2, 3)
test_4pt <- c(1, 2, 3, 4, -1, 0, 7, 8, 9, NA, 1, 2, 3, 4)
test_5pt <- c(1, 2, 3, 4, 5, -1, 0, 7, 8, 9, NA, 1, 2, 3, 4, 5)

# Test safe_3pt_none
cat("1. Testing safe_3pt_none:\n")
result_3pt <- safe_3pt_none(test_3pt)
cat("   Input:  ", paste(test_3pt, collapse = ", "), "\n")
cat("   Output: ", paste(result_3pt, collapse = ", "), "\n")

# Verify: valid values unchanged, missing codes -> NA
valid_3pt <- test_3pt[test_3pt %in% 1:3 & !is.na(test_3pt)]
result_valid_3pt <- result_3pt[test_3pt %in% 1:3 & !is.na(test_3pt)]
if (all(valid_3pt == result_valid_3pt, na.rm = TRUE)) {
  cat("   ✓ Valid values preserved (no reversal)\n")
} else {
  cat("   ❌ ERROR: Valid values changed!\n")
}

missing_3pt <- test_3pt[test_3pt %in% c(-1, 0, 7, 8, 9)]
result_missing_3pt <- result_3pt[test_3pt %in% c(-1, 0, 7, 8, 9)]
if (all(is.na(result_missing_3pt))) {
  cat("   ✓ Missing codes converted to NA\n\n")
} else {
  cat("   ❌ ERROR: Missing codes not converted!\n\n")
}

# Test safe_4pt_none
cat("2. Testing safe_4pt_none:\n")
result_4pt <- safe_4pt_none(test_4pt)
cat("   Input:  ", paste(test_4pt, collapse = ", "), "\n")
cat("   Output: ", paste(result_4pt, collapse = ", "), "\n")

valid_4pt <- test_4pt[test_4pt %in% 1:4 & !is.na(test_4pt)]
result_valid_4pt <- result_4pt[test_4pt %in% 1:4 & !is.na(test_4pt)]
if (all(valid_4pt == result_valid_4pt, na.rm = TRUE)) {
  cat("   ✓ Valid values preserved (no reversal)\n")
} else {
  cat("   ❌ ERROR: Valid values changed!\n")
}

missing_4pt <- test_4pt[test_4pt %in% c(-1, 0, 7, 8, 9)]
result_missing_4pt <- result_4pt[test_4pt %in% c(-1, 0, 7, 8, 9)]
if (all(is.na(result_missing_4pt))) {
  cat("   ✓ Missing codes converted to NA\n\n")
} else {
  cat("   ❌ ERROR: Missing codes not converted!\n\n")
}

# Test safe_5pt_none
cat("3. Testing safe_5pt_none:\n")
result_5pt <- safe_5pt_none(test_5pt)
cat("   Input:  ", paste(test_5pt, collapse = ", "), "\n")
cat("   Output: ", paste(result_5pt, collapse = ", "), "\n")

valid_5pt <- test_5pt[test_5pt %in% 1:5 & !is.na(test_5pt)]
result_valid_5pt <- result_5pt[test_5pt %in% 1:5 & !is.na(test_5pt)]
if (all(valid_5pt == result_valid_5pt, na.rm = TRUE)) {
  cat("   ✓ Valid values preserved (no reversal)\n")
} else {
  cat("   ❌ ERROR: Valid values changed!\n")
}

missing_5pt <- test_5pt[test_5pt %in% c(-1, 0, 7, 8, 9)]
result_missing_5pt <- result_5pt[test_5pt %in% c(-1, 0, 7, 8, 9)]
if (all(is.na(result_missing_5pt))) {
  cat("   ✓ Missing codes converted to NA\n\n")
} else {
  cat("   ❌ ERROR: Missing codes not converted!\n\n")
}

# Compare with reversal functions to show the difference
cat("4. Comparison with reversal functions:\n")
cat("   Original 4pt:  ", paste(test_4pt[1:4], collapse = ", "), "\n")
cat("   After none:    ", paste(result_4pt[1:4], collapse = ", "), " (identity)\n")
cat("   After reverse: ", paste(safe_reverse_4pt(test_4pt)[1:4], collapse = ", "), " (reversed)\n\n")

cat("=== All tests completed ===\n")
