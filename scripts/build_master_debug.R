#!/usr/bin/env Rscript
#' Build Master Dataset Directly from Specs
#'
#' Directly extracts source variables defined in YAML specs
#' and combines them into a master dataset

library(yaml)
library(dplyr)
library(here)

cat("\n=== BUILDING MASTER DATASET FROM SPECS ===\n\n")

# Load waves
cat("Loading waves...\n")
waves <- list(
  w1 = readRDS(here("data/processed/w1.rds")),
  w2 = readRDS(here("data/processed/w2.rds")),
  w3 = readRDS(here("data/processed/w3.rds")),
  w4 = readRDS(here("data/processed/w4.rds")),
  w5 = readRDS(here("data/processed/w5.rds")),
  w6 = readRDS(here("data/processed/w6.rds"))
)

cat("✓ Loaded 6 waves\n\n")

# ============================================================================
# BUILD MASTER FROM SPECS
# ============================================================================

spec_files <- c(
  "authoritarianism_democracy_scale",
  "community_leader_contact",
  "democracy_satisfaction",
  "economy",
  "government_leader_accountability",
  "hierarchical_obedience",
  "institutional_trust",
  "local_government_corruption",
  "national_government_corruption",
  "strong_leader_preference",
  "upright_leader_discretion"
)

cat("=== EXTRACTING VARIABLES FROM SPECS ===\n\n")

all_variable_data <- list()
variable_metadata <- data.frame(
  concept = character(),
  variable_id = character(),
  num_waves = integer(),
  waves_available = character(),
  stringsAsFactors = FALSE
)

output_dir <- here("outputs")

for (spec_file in spec_files) {
  cat("Processing:", spec_file, "\n")
  
  # Load spec
  spec_path <- here("src/config/harmonize", paste0(spec_file, ".yml"))
  spec <- read_yaml(spec_path)

  # Process each variable in spec (v2 format uses list with id field)
  for (idx in seq_along(spec$variables)) {
    var_spec <- spec$variables[[idx]]
    var_id <- var_spec$id

    if (is.null(var_id)) {
      next  # Skip if no id found
    }

    # Extract source columns (v2 format: source: {w1: q001, w2: q002})
    if (is.null(var_spec$source) || length(var_spec$source) == 0) {
      cat("  ✗ ", var_id, ": No source definition\n", sep="")
      next
    }

    source_cols <- var_spec$source
    var_data_by_wave <- list()
    waves_found <- character()
    
    for (wave_name in c("w1", "w2", "w3", "w4", "w5", "w6")) {
      col_name <- source_cols[[wave_name]]
      
      if (!is.null(col_name) && col_name %in% names(waves[[wave_name]])) {
        # Extract column
        col_data <- waves[[wave_name]][[col_name]]
        
        # Convert haven_labelled to numeric if needed
        if (inherits(col_data, 'haven_labelled')) {
          col_data <- as.numeric(unclass(col_data))
        }
        
        var_data_by_wave[[wave_name]] <- col_data
        waves_found <- c(waves_found, wave_name)
      }
    }
    
    if (length(var_data_by_wave) > 0) {
      # Store variable
      var_name <- paste(spec_file, var_id, sep = "_")
      all_variable_data[[var_name]] <- var_data_by_wave
      
      # Track metadata
      waves_str <- paste(waves_found, collapse = ",")
      variable_metadata <- rbind(
        variable_metadata,
        data.frame(
          concept = spec_file,
          variable_id = var_id,
          num_waves = length(var_data_by_wave),
          waves_available = waves_str,
          stringsAsFactors = FALSE
        )
      )
      
      cat("  ✓ ", var_id, " (", length(var_data_by_wave), " waves)\n", sep="")
    } else {
      cat("  ✗ ", var_id, ": No source columns found\n", sep="")
    }
  }
}

cat("\n✓ Extracted ", length(all_variable_data), " variables\n", sep="")

# ============================================================================
# BUILD WAVE-SPECIFIC DATASETS (WIDE FORMAT)
# ============================================================================

cat("\n=== CREATING WAVE-SPECIFIC DATASETS ===\n\n")

wave_datasets <- list()

for (wave_name in c("w1", "w2", "w3", "w4", "w5", "w6")) {
  wave_cols <- list()
  
  for (var_name in names(all_variable_data)) {
    var_data <- all_variable_data[[var_name]]
    
    if (wave_name %in% names(var_data)) {
      wave_cols[[var_name]] <- var_data[[wave_name]]
    }
  }
  
  if (length(wave_cols) > 0) {
    # Create data frame
    wave_df <- as.data.frame(wave_cols, check.names = FALSE)
    wave_datasets[[wave_name]] <- wave_df
    
    # Save
    wave_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(wave_df, wave_file)
    
    cat("  ", wave_name, ": saved with ", nrow(wave_df), " rows × ", ncol(wave_df), " variables\n", sep="")
  }
}

# ============================================================================
# BUILD LONG FORMAT
# ============================================================================

cat("\n=== CREATING LONG FORMAT ===\n\n")

master_long_list <- list()

for (var_name in names(all_variable_data)) {
  var_data <- all_variable_data[[var_name]]
  
  for (wave_name in names(var_data)) {
    values <- var_data[[wave_name]]
    
    for (i in seq_along(values)) {
      master_long_list[[length(master_long_list) + 1]] <- list(
        variable = var_name,
        wave = wave_name,
        row_id = i,
        value = values[i]
      )
    }
  }
}

master_long <- do.call(rbind, lapply(master_long_list, function(x) {
  data.frame(
    variable = x$variable,
    wave = x$wave,
    row_id = x$row_id,
    value = x$value,
    stringsAsFactors = FALSE
  )
}))

# Save long format
long_file <- file.path(output_dir, "master_long_format.rds")
saveRDS(master_long, long_file)

long_csv <- file.path(output_dir, "master_long_format.csv")
write.csv(master_long, long_csv, row.names = FALSE)

cat("  Long format: ", nrow(master_long), " rows × ", ncol(master_long), " columns\n", sep="")
cat("  CSV export: ", format(file.size(long_csv), big.mark=","), " bytes\n", sep="")

# ============================================================================
# VARIABLE SUMMARY
# ============================================================================

cat("\n=== CONSOLIDATED VARIABLE SUMMARY ===\n\n")

total_consolidated_vars <- nrow(variable_metadata)
total_wave_combos <- sum(variable_metadata$num_waves)

cat("| Concept | Variables | Wave Combos |\n")
cat("|---------|-----------|------------|\n")

for (concept in sort(unique(variable_metadata$concept))) {
  concept_rows <- variable_metadata[variable_metadata$concept == concept, ]
  num_vars <- nrow(concept_rows)
  num_combos <- sum(concept_rows$num_waves)
  cat("| ", concept, " | ", num_vars, " | ", num_combos, " |\n", sep="")
}

cat("\n**TOTALS**:\n")
cat("  Concepts: ", length(unique(variable_metadata$concept)), "\n", sep="")
cat("  Consolidated Variables: ", total_consolidated_vars, "\n", sep="")
cat("  Variable-Wave Combinations: ", total_wave_combos, "\n", sep="")

# ============================================================================
# SAVE METADATA
# ============================================================================

metadata_file <- file.path(output_dir, "master_variable_metadata.csv")
write.csv(variable_metadata, metadata_file, row.names = FALSE)
cat("\n✓ Saved metadata to: ", basename(metadata_file), "\n", sep="")

# ============================================================================
# GENERATE REPORT
# ============================================================================

cat("\n=== GENERATING REPORT ===\n")

report_content <- sprintf(
"# Master Harmonized Dataset Report

**Date**: %s

## Executive Summary

Successfully extracted and combined all harmonized variables into master datasets.

### Consolidated Variable Count: **%d**

### Key Statistics

| Metric | Value |
|--------|-------|
| Concepts | %d |
| **Consolidated Variables** | **%d** |
| Variable-Wave Combinations | %d |
| Total Data Points (Long Format) | %d |

## Consolidated Variables by Concept

| Concept | Variables | Wave Combinations |
|---------|-----------|------------------|
%s

## Output Datasets

### Wave-Specific Files (Wide Format - Recommended)
- `master_w1.rds` - %d rows × %d columns
- `master_w2.rds` - %d rows × %d columns
- `master_w3.rds` - %d rows × %d columns
- `master_w4.rds` - %d rows × %d columns
- `master_w5.rds` - %d rows × %d columns
- `master_w6.rds` - %d rows × %d columns

### Combined Format
- `master_long_format.rds` - Long format (%d rows × %d columns)
- `master_long_format.csv` - CSV export

### Metadata
- `master_variable_metadata.csv` - Variable definitions

## Complete Variable Listing

%s

## Data Structure

### Wave-Specific Datasets (Recommended)
Each wave file contains all available variables for that wave in wide format:
```r
# Load wave-specific data
w1_data <- readRDS('outputs/master_w1.rds')
# Each column is a consolidated variable
# Each row is a respondent
```

### Long Format
Alternative stacked format with columns:
- `variable` - variable name
- `wave` - wave (w1-w6)
- `row_id` - respondent ID
- `value` - variable value

## Usage Examples

```r
# Load and inspect
w1 <- readRDS('outputs/master_w1.rds')
dim(w1)  # Check dimensions
names(w1)  # List variables

# Cross-wave analysis
w1_vars <- readRDS('outputs/master_w1.rds')
w2_vars <- readRDS('outputs/master_w2.rds')

# Get specific variable across waves
econ_w1 <- w1_vars$economy_econ_national_now
econ_w2 <- w2_vars$economy_econ_national_now
```

---

**Report Generated**: %s
**Total Consolidated Variables: %d**
",
  format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  total_consolidated_vars,
  length(unique(variable_metadata$concept)),
  total_consolidated_vars,
  total_wave_combos,
  nrow(master_long),
  paste(sapply(sort(unique(variable_metadata$concept)), function(c) {
    subset_data <- variable_metadata[variable_metadata$concept == c, ]
    sprintf("| %s | %d | %d |", c, nrow(subset_data), sum(subset_data$num_waves))
  }), collapse = "\n"),
  nrow(wave_datasets$w1), ncol(wave_datasets$w1),
  nrow(wave_datasets$w2), ncol(wave_datasets$w2),
  nrow(wave_datasets$w3), ncol(wave_datasets$w3),
  nrow(wave_datasets$w4), ncol(wave_datasets$w4),
  nrow(wave_datasets$w5), ncol(wave_datasets$w5),
  nrow(wave_datasets$w6), ncol(wave_datasets$w6),
  nrow(master_long), ncol(master_long),
  paste(sapply(sort(unique(variable_metadata$concept)), function(c) {
    cat_text <- paste0("### ", c, " (", nrow(variable_metadata[variable_metadata$concept == c, ]), " variables)\n\n")
    subset_data <- variable_metadata[variable_metadata$concept == c, ]
    for (i in seq_len(nrow(subset_data))) {
      row <- subset_data[i, ]
      cat_text <- paste0(cat_text, "- `", c, "_", row$variable_id, "` (",
                        row$num_waves, " waves: ", row$waves_available, ")\n")
    }
    cat_text
  }), collapse = "\n"),
  format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  total_consolidated_vars
)

report_file <- file.path(output_dir, "MASTER_DATASET_SUMMARY.md")
writeLines(report_content, report_file)
cat("✓ Report saved to: ", basename(report_file), "\n", sep="")

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
cat("MASTER DATASET CREATION COMPLETE\n")
cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")

cat("CONSOLIDATED VARIABLE COUNT: **", total_consolidated_vars, "**\n\n", sep="")

cat("Summary:\n")
cat("  ✓ Concepts: ", length(unique(variable_metadata$concept)), "\n", sep="")
cat("  ✓ Consolidated Variables: ", total_consolidated_vars, "\n", sep="")
cat("  ✓ Variable-Wave Combinations: ", total_wave_combos, "\n", sep="")
cat("  ✓ Wave-Specific Files: 6 (wide format)\n")
cat("  ✓ Long Format: 1 RDS + 1 CSV\n")
cat("  ✓ Metadata: CSV + Markdown Report\n\n")

cat("Output Files:\n")
cat("  - master_w1.rds through master_w6.rds\n")
cat("  - master_long_format.rds & .csv\n")
cat("  - master_variable_metadata.csv\n")
cat("  - MASTER_DATASET_SUMMARY.md\n\n")

cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
