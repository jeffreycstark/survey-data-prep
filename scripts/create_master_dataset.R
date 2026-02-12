#!/usr/bin/env Rscript
#' Create Master Harmonized Dataset
#' 
#' Directly harmonizes all concepts and combines into master dataset

library(yaml)
library(dplyr)
library(here)

cat("\n=== CREATING MASTER HARMONIZED DATASET ===\n\n")

# Load functions
source(here("src/r/harmonize/_load_harmonize.R"))
source(here("src/r/utils/_load_functions.R"))

# Load waves
cat("Loading data waves...\n")
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
# HARMONIZE AND COMBINE
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

cat("=== HARMONIZING AND COMBINING ===\n\n")

all_variables <- list()
variable_metadata <- data.frame(
  concept = character(),
  variable_id = character(),
  num_waves = integer(),
  wave_names = character(),
  stringsAsFactors = FALSE
)

for (spec_file in spec_files) {
  cat("Processing:", spec_file, "\n")
  
  tryCatch({
    # Load spec
    spec_path <- here("src/config/harmonize", paste0(spec_file, ".yml"))
    spec <- read_yaml(spec_path)
    num_vars <- length(spec$variables)
    
    # Harmonize
    harmonized <- harmonize_all(spec, waves)
    
    # Process variables
    for (var_id in names(harmonized)) {
      var_data <- harmonized[[var_id]]
      
      if (!is.null(var_data) && length(var_data) > 0) {
        # Store variable
        col_name <- paste(spec_file, var_id, sep = "_")
        all_variables[[col_name]] <- var_data
        
        # Track metadata
        wave_names <- paste(names(var_data), collapse = ",")
        variable_metadata <- rbind(
          variable_metadata,
          data.frame(
            concept = spec_file,
            variable_id = var_id,
            num_waves = length(var_data),
            wave_names = wave_names,
            stringsAsFactors = FALSE
          )
        )
        
        cat("  ✓", var_id, "(", length(var_data), "waves)\n")
      }
    }
    
  }, error = function(e) {
    cat("  ✗ Error:", e$message, "\n")
  })
}

cat("\n✓ Processed all concepts\n")
cat("  Total variables collected: ", length(all_variables), "\n", sep="")

# ============================================================================
# BUILD MASTER DATASETS
# ============================================================================

cat("\n=== BUILDING MASTER DATASETS ===\n\n")

output_dir <- here("outputs")

# Wave-specific datasets
cat("Creating wave-specific datasets...\n")

wave_datasets <- list()

for (wave_name in c("w1", "w2", "w3", "w4", "w5", "w6")) {
  wave_vars <- list()
  
  for (col_name in names(all_variables)) {
    var_data <- all_variables[[col_name]]
    
    if (wave_name %in% names(var_data)) {
      wave_vars[[col_name]] <- var_data[[wave_name]]
    }
  }
  
  if (length(wave_vars) > 0) {
    # Create data frame
    wave_df <- as.data.frame(wave_vars, check.names = FALSE)
    wave_datasets[[wave_name]] <- wave_df
    
    cat("  ", wave_name, ": ", nrow(wave_df), " rows × ", ncol(wave_df), " columns\n", sep="")
    
    # Save
    wave_file <- file.path(output_dir, paste0("master_", wave_name, ".rds"))
    saveRDS(wave_df, wave_file)
  }
}

# Long format (stacked all variables)
cat("\nCreating long-format master dataset...\n")

master_long <- data.frame(
  row_id = integer(),
  wave = character(),
  variable = character(),
  value = numeric(),
  stringsAsFactors = FALSE
)

row_counter <- 1
for (col_name in names(all_variables)) {
  var_data <- all_variables[[col_name]]
  
  for (wave_name in names(var_data)) {
    values <- var_data[[wave_name]]
    for (i in seq_along(values)) {
      master_long <- rbind(
        master_long,
        data.frame(
          row_id = i,
          wave = wave_name,
          variable = col_name,
          value = values[i],
          stringsAsFactors = FALSE
        )
      )
    }
  }
}

cat("  Master long format: ", nrow(master_long), " rows × ", ncol(master_long), " columns\n", sep="")

# Save long format
long_file <- file.path(output_dir, "master_long_format.rds")
saveRDS(master_long, long_file)

# Save as CSV
long_csv <- file.path(output_dir, "master_long_format.csv")
write.csv(master_long, long_csv, row.names = FALSE)
cat("  CSV export: ", format(file.size(long_csv), big.mark=","), " bytes\n", sep="")

# ============================================================================
# STATISTICS
# ============================================================================

cat("\n=== VARIABLE SUMMARY ===\n\n")

# Count by concept
concept_counts <- table(variable_metadata$concept)

total_consolidated_vars <- nrow(variable_metadata)
total_wave_combinations <- sum(variable_metadata$num_waves)

cat("Consolidated Variables by Concept:\n\n")
cat("| Concept | Variables | Wave-Combinations |\n")
cat("|---------|-----------|------------------|\n")

for (concept in sort(unique(variable_metadata$concept))) {
  subset_data <- variable_metadata[variable_metadata$concept == concept, ]
  num_vars <- nrow(subset_data)
  num_combos <- sum(subset_data$num_waves)
  cat("| ", concept, " | ", num_vars, " | ", num_combos, " |\n", sep="")
}

cat("\n**TOTALS**:\n")
cat("  Concepts: ", length(unique(variable_metadata$concept)), "\n", sep="")
cat("  Consolidated Variables: ", total_consolidated_vars, "\n", sep="")
cat("  Variable-Wave Combinations: ", total_wave_combinations, "\n", sep="")

# ============================================================================
# DETAILED REPORT
# ============================================================================

cat("\n=== DETAILED VARIABLE LISTING ===\n\n")

for (concept in sort(unique(variable_metadata$concept))) {
  cat(concept, ":\n")
  subset_data <- variable_metadata[variable_metadata$concept == concept, ]
  for (i in seq_len(nrow(subset_data))) {
    row <- subset_data[i, ]
    cat("  -", row$variable_id, "(", row$num_waves, "waves: ", row$wave_names, ")\n", sep="")
  }
  cat("\n")
}

# ============================================================================
# SAVE METADATA
# ============================================================================

cat("Saving metadata...\n")

metadata_file <- file.path(output_dir, "master_variable_metadata.csv")
write.csv(variable_metadata, metadata_file, row.names = FALSE)
cat("✓ Saved variable metadata\n")

# ============================================================================
# FINAL REPORT
# ============================================================================

report_content <- sprintf(
"# Master Harmonized Dataset - Summary

**Date**: %s

## Dataset Summary

### Consolidated Variables

- **Total Concepts**: %d
- **Total Consolidated Variables**: %d
- **Total Variable-Wave Combinations**: %d

### Output Datasets

**Wave-Specific Files (Wide Format)**:
- `master_w1.rds` - Wave 1 data (%d rows × %d columns)
- `master_w2.rds` - Wave 2 data (%d rows × %d columns)
- `master_w3.rds` - Wave 3 data (%d rows × %d columns)
- `master_w4.rds` - Wave 4 data (%d rows × %d columns)
- `master_w5.rds` - Wave 5 data (%d rows × %d columns)
- `master_w6.rds` - Wave 6 data (%d rows × %d columns)

**Combined Formats**:
- `master_long_format.rds` - Long format (%d rows)
- `master_long_format.csv` - CSV export (%d rows)

**Metadata**:
- `master_variable_metadata.csv` - Variable documentation

## Consolidated Variables by Concept

| Concept | Variables | Wave-Combinations |
|---------|-----------|------------------|
%s

## Complete Variable Listing

%s

## Usage

### Load Wave-Specific Data (Recommended)
```r
w1_data <- readRDS('outputs/master_w1.rds')  # n=%d rows × %d cols
w2_data <- readRDS('outputs/master_w2.rds')  # n=%d rows × %d cols
# ... w3 through w6 available
```

### Load Long Format
```r
long_data <- readRDS('outputs/master_long_format.rds')
```

### Access Variable Metadata
```r
metadata <- read.csv('outputs/master_variable_metadata.csv')
```

---
**Total Consolidated Variables**: %d
**Total Variable-Wave Combinations**: %d
",
  format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  length(unique(variable_metadata$concept)),
  total_consolidated_vars,
  total_wave_combinations,
  nrow(wave_datasets$w1), ncol(wave_datasets$w1),
  nrow(wave_datasets$w2), ncol(wave_datasets$w2),
  nrow(wave_datasets$w3), ncol(wave_datasets$w3),
  nrow(wave_datasets$w4), ncol(wave_datasets$w4),
  nrow(wave_datasets$w5), ncol(wave_datasets$w5),
  nrow(wave_datasets$w6), ncol(wave_datasets$w6),
  nrow(master_long), nrow(master_long),
  paste(sapply(sort(unique(variable_metadata$concept)), function(c) {
    subset_data <- variable_metadata[variable_metadata$concept == c, ]
    sprintf("| %s | %d | %d |", c, nrow(subset_data), sum(subset_data$num_waves))
  }), collapse = "\n"),
  paste(sapply(sort(unique(variable_metadata$concept)), function(c) {
    cat_text <- paste0("### ", c, "\n")
    subset_data <- variable_metadata[variable_metadata$concept == c, ]
    for (i in seq_len(nrow(subset_data))) {
      row <- subset_data[i, ]
      cat_text <- paste0(cat_text, "- ", row$variable_id, " (", row$num_waves, " waves: ", row$wave_names, ")\n")
    }
    cat_text
  }), collapse = "\n"),
  nrow(wave_datasets$w1), ncol(wave_datasets$w1),
  nrow(wave_datasets$w2), ncol(wave_datasets$w2),
  total_consolidated_vars,
  total_wave_combinations
)

report_file <- file.path(output_dir, "MASTER_DATASET_SUMMARY.md")
writeLines(report_content, report_file)
cat("✓ Report saved\n")

# ============================================================================
# FINAL SUMMARY
# ============================================================================

cat("\n", paste(rep("=", 70), collapse=""), "\n", sep="")
cat("MASTER DATASET CREATION COMPLETE\n")
cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")

cat("RESULTS:\n\n")
cat("  ✓ Concepts Combined: ", length(unique(variable_metadata$concept)), "\n", sep="")
cat("  ✓ Consolidated Variables: ", total_consolidated_vars, "\n", sep="")
cat("  ✓ Variable-Wave Combinations: ", total_wave_combinations, "\n", sep="")
cat("  ✓ Wave-Specific Files: 6\n")
cat("  ✓ Combined Long Format: 1 RDS + 1 CSV\n")
cat("  ✓ Metadata Files: 1 CSV\n\n")

cat("Output Files Generated:\n")
cat("  - master_w1.rds through master_w6.rds (wave-specific, wide format)\n")
cat("  - master_long_format.rds (all variables stacked)\n")
cat("  - master_long_format.csv (CSV export)\n")
cat("  - master_variable_metadata.csv (variable documentation)\n")
cat("  - MASTER_DATASET_SUMMARY.md (this summary)\n\n")

cat(paste(rep("=", 70), collapse=""), "\n\n", sep="")
