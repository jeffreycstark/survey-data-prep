#!/usr/bin/env Rscript

# Quick check: what are the actual variable labels in the SPSS files?

source(here::here("src", "r", "utils", "load_data.R"))

cat("\n=== LOADING WAVES ===\n")
waves <- load_survey_waves()

# Check Wave 1
cat("\n=== WAVE 1: First 20 variable names and their labels ===\n")
w1 <- waves$w1
var_labels_w1 <- attr(w1, "variable.labels")

for (i in 1:min(20, length(names(w1)))) {
  var_name <- names(w1)[i]
  var_label <- var_labels_w1[[var_name]] %||% "(no label)"
  cat(sprintf("%3d. %-12s | %s\n", i, var_name, var_label))
}

# Check q7-q20 specifically
cat("\n=== WAVE 1: Variables q7-q20 ===\n")
q_vars <- grep("^q(0?(7|8|9|1[0-9]|20))$", names(w1), ignore.case = TRUE, value = TRUE)
cat(sprintf("Found %d variables matching q7-q20 pattern\n\n", length(q_vars)))

for (var_name in q_vars) {
  var_label <- var_labels_w1[[var_name]] %||% "(no label)"
  cat(sprintf("%-12s | %s\n", var_name, var_label))
}

# Check Wave 2
cat("\n\n=== WAVE 2: Variables q7-q20 ===\n")
w2 <- waves$w2
var_labels_w2 <- attr(w2, "variable.labels")
q_vars_w2 <- grep("^q(0?(7|8|9|1[0-9]|20))$", names(w2), ignore.case = TRUE, value = TRUE)
cat(sprintf("Found %d variables matching q7-q20 pattern\n\n", length(q_vars_w2)))

for (var_name in q_vars_w2[1:15]) {
  var_label <- var_labels_w2[[var_name]] %||% "(no label)"
  cat(sprintf("%-12s | %s\n", var_name, var_label))
}
