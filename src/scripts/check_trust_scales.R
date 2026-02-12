#!/usr/bin/env Rscript
# Check actual value ranges for institutional trust variables

library(haven)
library(dplyr)
library(here)

source(here::here("src", "r", "data_prep_modules", "0_load_waves.R"))

cat("\n=== CHECKING INSTITUTIONAL TRUST VALUE RANGES ===\n")

waves <- load_waves()

# Check a few trust variables
vars_to_check <- list(
  w1 = "q011",
  w2 = "q12",
  w3 = "q12",
  w4 = "q12",
  w5 = "q12",
  w6 = "q12"
)

cat("\nTrust in Civil Service (q011/q12) value ranges:\n")
for (wave in names(vars_to_check)) {
  var <- vars_to_check[[wave]]
  data <- waves[[wave]][[var]]

  # Convert to numeric to see raw values
  num_data <- as.numeric(data)

  cat(sprintf("\n%s (%s):\n", wave, var))
  cat(sprintf("  Min: %s, Max: %s, Mean: %.2f\n",
              min(num_data, na.rm = TRUE),
              max(num_data, na.rm = TRUE),
              mean(num_data, na.rm = TRUE)))

  cat(sprintf("  Value counts:\n"))
  tbl <- table(num_data, useNA = "always")
  print(head(tbl, 15))
}

cat("\n\nChecking for missing codes:\n")
for (wave in c("w1", "w2", "w3")) {
  var <- vars_to_check[[wave]]
  data <- as.numeric(waves[[wave]][[var]])

  missing_codes <- c(-2, -1, 0, 7, 8, 9, 99)
  found <- missing_codes[missing_codes %in% data]

  if (length(found) > 0) {
    cat(sprintf("%s: Found codes %s\n", wave, paste(found, collapse = ", ")))
  }
}
