#!/usr/bin/env Rscript

# Check how haven stores variable labels and value labels

source(here::here("src", "r", "utils", "load_data.R"))

cat("\n=== LOADING WAVE 1 ===\n")
w1 <- haven::read_sav(here::here("data", "raw", "wave1", "Wave1_20170906.sav"))

cat("\n=== STRUCTURE OF A VARIABLE ===\n")
# Look at q010
var <- w1$q010
cat("Variable: q010\n")
cat("Class:", class(var), "\n")
cat("Attributes:\n")
str(attributes(var))

cat("\n=== TRYING DIFFERENT WAYS TO GET LABELS ===\n")

# Method 1: attr(data, "variable.labels")
var_labels_1 <- attr(w1, "variable.labels")
cat("Method 1 - attr(w1, 'variable.labels'):", !is.null(var_labels_1), "\n")

# Method 2: Look for label attribute on column
label_q010 <- attr(w1$q010, "label")
cat("Method 2 - attr(col, 'label'):", label_q010, "\n")

# Method 3: Look at names of columns
cat("\nColumn names (first 15):\n")
print(names(w1)[1:15])

# Method 4: Check if there's a labelled class
cat("\nClass of w1$q010:", class(w1$q010), "\n")

# Method 5: Use haven functions
if (require(haven, quietly = TRUE)) {
  cat("\nUsing haven::as_factor() to see if there's structure:\n")
  fact <- haven::as_factor(w1$q010)
  cat("Factor levels:", levels(fact), "\n")
}

cat("\n=== CHECK MULTIPLE VARIABLES ===\n")
for (i in c(1:5, 40:45)) {
  col_name <- names(w1)[i]
  col_label <- attr(w1[[col_name]], "label")
  if (is.null(col_label)) col_label <- "(no label)"
  cat(sprintf("%3d. %-15s | %s\n", i, col_name, col_label))
}

cat("\n=== CHECK DATA ATTRIBUTES ===\n")
cat("All attributes of w1:\n")
print(names(attributes(w1)))
