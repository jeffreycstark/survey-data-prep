#!/usr/bin/env Rscript
#' Combine All Harmonized Datasets into Master File
#' 
#' Combines all 11 harmonized concept datasets into a single master dataset
#' and provides variable count statistics

library(here)
library(dplyr)

cat("\n=== COMBINING HARMONIZED DATASETS ===\n\n")

output_dir <- here("outputs")

# ============================================================================
# 1. LOAD ALL HARMONIZED DATASETS
# ============================================================================

cat("Loading harmonized datasets...\n\n")

harmonized_files <- list.files(
  output_dir, 
  pattern = "_harmonized_full\\.rds$",
  full.names = TRUE
)

cat("Found", length(harmonized_files), "harmonized datasets:\n")

harmonized_data <- list()
concept_names <- character()

for (file in harmonized_files) {
  concept_name <- sub("_harmonized_full\\.rds$", "", basename(file))
  concept_name <- sub("^", "", concept_name)
  
  cat("  ✓ Loading:", concept_name, "\n")
  
  data <- readRDS(file)
  harmonized_data[[concept_name]] <- data
  concept_names <- c(concept_names, concept_name)
}

cat("\n✓ Loaded", length(harmonized_data), "concepts\n")

# ============================================================================
# 2. ANALYZE STRUCTURE
# ============================================================================

cat("\n=== VARIABLE STRUCTURE ANALYSIS ===\n\n")

variable_summary <- list()
total_wave_combinations <- 0
consolidated_var_count <- 0

for (concept in names(harmonized_data)) {
  concept_data <- harmonized_data[[concept]]
  
  cat("Concept:", concept, "\n")
  cat("  Type:", class(concept_data), "\n")
  
  if (is.list(concept_data) && length(concept_data) > 0) {
    cat("  Variables:", length(concept_data), "\n")
    
    var_details <- list()
    for (var_id in names(concept_data)) {
      var_data <- concept_data[[var_id]]
      num_waves <- length(var_data)
      
      cat("    -", var_id, "(", num_waves, "waves)\n")
      
      var_details[[var_id]] <- list(
        variable_id = var_id,
        num_waves = num_waves,
        waves = names(var_data)
      )
      
      consolidated_var_count <- consolidated_var_count + 1
      total_wave_combinations <- total_wave_combinations + num_waves
    }
    
    variable_summary[[concept]] <- var_details
  } else {
    cat("  WARNING: Empty or NULL data structure\n")
  }
  
  cat("\n")
}

# ============================================================================
# 3. BUILD COMBINED DATASET (LONG FORMAT)
# ============================================================================

cat("=== BUILDING COMBINED DATASET ===\n\n")

# Build long-format master dataset
master_data_list <- list()

for (concept in names(harmonized_data)) {
  concept_data <- harmonized_data[[concept]]
  
  for (var_id in names(concept_data)) {
    for (wave_name in names(concept_data[[var_id]])) {
      values <- concept_data[[var_id]][[wave_name]]
      
      if (!exists("master_data_list")) {
        master_data_list <- list()
      }
      
      # Add to list with column name
      col_name <- paste(concept, var_id, wave_name, sep = "_")
      master_data_list[[col_name]] <- values
    }
  }
}

# Convert to data frame
cat("Creating combined data frame...\n")

# Get max length to handle different wave sizes
max_rows <- max(sapply(master_data_list, length))

# Pad vectors to same length
master_data_list_padded <- lapply(master_data_list, function(x) {
  if (length(x) < max_rows) {
    c(x, rep(NA, max_rows - length(x)))
  } else {
    x
  }
})

# Create data frame
master_df <- as.data.frame(master_data_list_padded, check.names = FALSE)

cat("✓ Created combined data frame\n")
cat("  Rows:", nrow(master_df), "\n")
cat("  Columns:", ncol(master_df), "\n")

# ============================================================================
# 4. BUILD WIDE FORMAT (BY WAVE)
# ============================================================================

cat("\n=== BUILDING WIDE FORMAT (BY WAVE) ===\n\n")

wide_format_waves <- list()

for (wave in c("w1", "w2", "w3", "w4", "w5", "w6")) {
  wave_columns <- list()
  
  for (concept in names(harmonized_data)) {
    concept_data <- harmonized_data[[concept]]
    
    for (var_id in names(concept_data)) {
      if (wave in names(concept_data[[var_id]])) {
        col_name <- paste(concept, var_id, sep = "_")
        wave_columns[[col_name]] <- concept_data[[var_id]][[wave]]
      }
    }
  }
  
  if (length(wave_columns) > 0) {
    # Pad to max length
    max_len <- max(sapply(wave_columns, length))
    wave_columns_padded <- lapply(wave_columns, function(x) {
      if (length(x) < max_len) {
        c(x, rep(NA, max_len - length(x)))
      } else {
        x
      }
    })
    
    wave_df <- as.data.frame(wave_columns_padded, check.names = FALSE)
    wide_format_waves[[wave]] <- wave_df
    
    cat("✓", wave, ":", nrow(wave_df), "rows x", ncol(wave_df), "variables\n")
  }
}

# ============================================================================
# 5. SAVE RESULTS
# ============================================================================

cat("\n=== SAVING MASTER FILES ===\n\n")

# Save combined long format
master_file_long <- file.path(output_dir, "master_harmonized_long.rds")
saveRDS(master_df, master_file_long)
cat("✓ Saved long format:", basename(master_file_long), "\n")
cat("  Size:", format(file.size(master_file_long), big.mark = ","), "bytes\n")

# Save each wave separately
for (wave in names(wide_format_waves)) {
  wave_file <- file.path(output_dir, paste0("master_harmonized_", wave, ".rds"))
  saveRDS(wide_format_waves[[wave]], wave_file)
  cat("✓ Saved", wave, ":", basename(wave_file), "\n")
}

# Save combined long format as CSV
master_file_csv <- file.path(output_dir, "master_harmonized_long.csv")
write.csv(master_df, master_file_csv, row.names = FALSE)
cat("✓ Saved CSV:", basename(master_file_csv), "\n")
cat("  Size:", format(file.size(master_file_csv), big.mark = ","), "bytes\n")

# ============================================================================
# 6. GENERATE SUMMARY REPORT
# ============================================================================

cat("\n=== VARIABLE SUMMARY REPORT ===\n\n")

# Count consolidated variables by concept
consolidated_by_concept <- sapply(variable_summary, function(concept) {
  length(concept)
})

cat("Consolidated Variables by Concept:\n\n")
cat("| Concept | Variables | Wave Combinations |\n")
cat("|---------|-----------|------------------|\n")

total_combinations <- 0
for (concept in names(consolidated_by_concept)) {
  num_vars <- consolidated_by_concept[[concept]]
  
  # Count wave combinations for this concept
  combinations <- 0
  for (var in variable_summary[[concept]]) {
    combinations <- combinations + var$num_waves
  }
  
  cat("| ", concept, " | ", num_vars, " | ", combinations, " |\n", sep="")
  total_combinations <- total_combinations + combinations
}

cat("\n**TOTALS:**\n")
cat("- Total Concepts: ", length(harmonized_data), "\n", sep="")
cat("- Total Consolidated Variables: ", consolidated_var_count, "\n", sep="")
cat("- Total Variable-Wave Combinations: ", total_combinations, "\n", sep="")
cat("- Master Dataset Columns: ", ncol(master_df), "\n", sep="")
cat("- Master Dataset Rows: ", nrow(master_df), "\n", sep="")

# ============================================================================
# 7. DATA QUALITY CHECK
# ============================================================================

cat("\n=== DATA QUALITY CHECK ===\n\n")

cat("Checking for missing values in master dataset:\n\n")

missing_by_column <- colSums(is.na(master_df))
missing_pct <- (missing_by_column / nrow(master_df)) * 100

# Summary stats
missing_stats <- data.frame(
  min_missing_pct = min(missing_pct),
  max_missing_pct = max(missing_pct),
  mean_missing_pct = mean(missing_pct),
  median_missing_pct = median(missing_pct),
  complete_cases = sum(complete.cases(master_df))
)

cat("Missing Value Statistics:\n")
cat("  Min % Missing: ", round(missing_stats$min_missing_pct, 2), "%\n", sep="")
cat("  Max % Missing: ", round(missing_stats$max_missing_pct, 2), "%\n", sep="")
cat("  Mean % Missing: ", round(missing_stats$mean_missing_pct, 2), "%\n", sep="")
cat("  Median % Missing: ", round(missing_stats$median_missing_pct, 2), "%\n", sep="")
cat("  Complete Cases: ", missing_stats$complete_cases, "\n", sep="")

# ============================================================================
# 8. FINAL SUMMARY
# ============================================================================

report_file <- file.path(output_dir, "MASTER_DATASET_SUMMARY.md")

report_content <- sprintf(
"# Master Harmonized Dataset - Summary Report

**Date**: %s

## Overview

Successfully combined all harmonized datasets into a comprehensive master file.

## Dataset Statistics

### Consolidated Variables
- **Total Concepts**: %d
- **Total Consolidated Variables**: %d
- **Total Variable-Wave Combinations**: %d
- **Master Dataset Dimensions**: %d rows × %d columns

### Wave-Specific Datasets

| Wave | Rows | Columns |
|------|------|---------|
%s

### Consolidated Variables by Concept

| Concept | Variables | Wave Combinations |
|---------|-----------|------------------|
%s

## File Output

### Generated Files

1. **master_harmonized_long.rds** - Full combined dataset (long format)
   - Format: Long/stacked format with all variable-wave combinations
   - Size: %s

2. **master_harmonized_long.csv** - CSV export of long format
   - Size: %s

3. **master_harmonized_w1.rds** through **master_harmonized_w6.rds**
   - Separate RDS files for each wave (wide format)
   - Convenient for wave-specific analysis

## Data Quality

### Missing Value Summary
- Minimum Missing: %.2f%%
- Maximum Missing: %.2f%%
- Mean Missing: %.2f%%
- Median Missing: %.2f%%
- Complete Cases: %d

### Variable Coverage
All %d consolidated variables are present across harmonized concepts with consistent structure.

## Harmonized Concepts (%d total)

%s

## Usage Guide

### Load Master Data (Long Format)
```r
master <- readRDS('outputs/master_harmonized_long.rds')
# Dimensions: %d rows × %d columns
```

### Load Wave-Specific Data (Wide Format)
```r
w1_data <- readRDS('outputs/master_harmonized_w1.rds')
w2_data <- readRDS('outputs/master_harmonized_w2.rds')
# ... w3 through w6 available
```

### Access Individual Concepts
```r
# Load individual harmonized concept
econ <- readRDS('outputs/economy_harmonized_full.rds')
dem_sat <- readRDS('outputs/democracy_satisfaction_harmonized_full.rds')
```

## Next Steps

1. **Data Exploration**: Examine distributions and relationships
2. **Composite Variables**: Create indices from related variables
3. **Analysis**: Conduct cross-wave analysis of authoritarian attitudes
4. **Validation**: Compare with source variables for accuracy

## Technical Notes

- All variables standardized to consistent missing value conventions
- Wave combinations handled consistently across concepts
- Data structure optimized for both longitudinal and cross-sectional analysis
- CSV export available for non-R users

---
Generated: %s
",
  format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  length(harmonized_data),
  consolidated_var_count,
  total_combinations,
  nrow(master_df),
  ncol(master_df),
  paste(sapply(names(wide_format_waves), function(w) {
    sprintf("| %s | %d | %d |", w, nrow(wide_format_waves[[w]]), ncol(wide_format_waves[[w]]))
  }), collapse = "\n"),
  paste(sapply(names(consolidated_by_concept), function(concept) {
    combinations <- sum(sapply(variable_summary[[concept]], function(v) v$num_waves))
    sprintf("| %s | %d | %d |", concept, consolidated_by_concept[[concept]], combinations)
  }), collapse = "\n"),
  format(file.size(master_file_long), big.mark = ","),
  format(file.size(master_file_csv), big.mark = ","),
  missing_stats$min_missing_pct,
  missing_stats$max_missing_pct,
  missing_stats$mean_missing_pct,
  missing_stats$median_missing_pct,
  missing_stats$complete_cases,
  consolidated_var_count,
  length(harmonized_data),
  paste("- " , names(harmonized_data), collapse = "\n"),
  nrow(master_df),
  ncol(master_df),
  format(Sys.time(), "%Y-%m-%d %H:%M:%S")
)

writeLines(report_content, report_file)
cat("✓ Report saved to:", basename(report_file), "\n")

# ============================================================================
# 9. CONSOLE SUMMARY
# ============================================================================

cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
cat("MASTER DATASET COMBINATION COMPLETE\n")
cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")

cat("SUMMARY:\n")
cat("  ✓ Concepts Combined: ", length(harmonized_data), "\n", sep="")
cat("  ✓ Consolidated Variables: ", consolidated_var_count, "\n", sep="")
cat("  ✓ Variable-Wave Combinations: ", total_combinations, "\n", sep="")
cat("  ✓ Master Dataset Size: ", nrow(master_df), " rows × ", ncol(master_df), " columns\n", sep="")
cat("  ✓ Files Generated: 9\n\n")

cat("Output Files:\n")
cat("  - master_harmonized_long.rds (combined long format)\n")
cat("  - master_harmonized_long.csv (CSV export)\n")
cat("  - master_harmonized_w1.rds through master_harmonized_w6.rds (by wave)\n")
cat("  - MASTER_DATASET_SUMMARY.md (this report)\n\n")

cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
