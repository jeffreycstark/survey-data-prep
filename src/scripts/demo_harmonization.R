#!/usr/bin/env Rscript

# Demo: Generate harmonization R code for civil_service
# This shows what the harmonization system produces from YAML config

library(yaml)
library(dplyr)
library(here)

cat("\n=== INSTITUTIONAL TRUST HARMONIZATION DEMO ===\n")
cat("Variable: civil_service\n")
cat("Purpose: Show generated R code from YAML specification\n\n")

# 1. Load YAML
yaml_file <- here::here("src", "config", "harmonize", "trust_civil_service.yml")
cat("Reading YAML from:", yaml_file, "\n")

if (!file.exists(yaml_file)) {
  cat("ERROR: File not found!\n")
  quit(status = 1)
}

yaml_spec <- yaml::read_yaml(yaml_file)

cat("\n=== YAML CONFIGURATION ===\n")
print(yaml_spec)

# 2. Generate R code template showing harmonization logic
cat("\n\n=== GENERATED HARMONIZATION CODE (TEMPLATE) ===\n\n")

# Extract variable info
var_name <- yaml_spec$variables[[1]]$name
var_id <- yaml_spec$variables[[1]]$id
var_label <- yaml_spec$variables[[1]]$label
sources <- yaml_spec$variables[[1]]$sources
harmonize_method <- yaml_spec$variables[[1]]$harmonize[[1]]$method
scale_type <- yaml_spec$variables[[1]]$scale$type
scale_min <- yaml_spec$variables[[1]]$scale$min_value
scale_max <- yaml_spec$variables[[1]]$scale$max_value
reversed <- yaml_spec$variables[[1]]$scale$reversed

cat("# Harmonized variable:", var_name, "\n")
cat("# Variable ID:", var_id, "\n")
cat("# Label:", var_label, "\n")
cat("# Concept: institutional_trust\n")
cat("# Method:", harmonize_method, "\n")
cat("# Scale: Likert (", scale_min, "-", scale_max, "), Reversed:", reversed, "\n")
cat("\n")

cat("# Source mapping:\n")
for (src in sources) {
  cat(sprintf("# - %s: %s (%s)\n", src$wave, src$variable, src$label))
}

cat("\n# ============================================================================\n")
cat("# HARMONIZATION CODE\n")
cat("# ============================================================================\n\n")

cat("library(dplyr)\n\n")

cat("# Load raw survey waves\n")
cat("waves <- list(\n")
for (src in sources) {
  wave <- src$wave
  cat(sprintf("  %s = readRDS(here::here('data', 'processed', '%s.rds')),\n", wave, wave))
}
cat(")\n\n")

cat("# Define variable extraction and harmonization logic\n")
cat(sprintf("harmonize_%s <- function(waves) {\n", var_name))
cat("  \n")
cat("  # Extract source variables from each wave\n")

for (src in sources) {
  wave <- src$wave
  variable <- src$variable
  cat(sprintf("  %s_raw <- waves$%s$%s\n", wave, wave, variable))
}

cat("\n  # Convert to numeric (in case of labelled SPSS data)\n")
for (src in sources) {
  wave <- src$wave
  cat(sprintf("  %s_numeric <- as.numeric(%s_raw)\n", wave, wave))
}

cat("\n  # Apply harmonization method: ", harmonize_method, "\n")
if (harmonize_method == "direct") {
  cat("  # All waves use identical 1-4 Likert scale - no transformation needed\n")
  cat("  \n")
  for (src in sources) {
    wave <- src$wave
    cat(sprintf("  %s_harmonized <- %s_numeric\n", wave, wave))
  }
} else if (grepl("reverse", harmonize_method)) {
  cat("  # Some waves have reversed scales - reverse them\n")
  cat("  \n")
  for (src in sources) {
    wave <- src$wave
    cat(sprintf("  # %s: %s\n", wave, src$label))
    if (grepl("4pt", harmonize_method)) {
      cat(sprintf("  %s_harmonized <- 5 - %s_numeric  # Reverse 4-point scale (4→1, 1→4)\n", wave, wave))
    } else if (grepl("5pt", harmonize_method)) {
      cat(sprintf("  %s_harmonized <- 6 - %s_numeric  # Reverse 5-point scale (5→1, 1→5)\n", wave, wave))
    }
  }
} else if (grepl("recode", harmonize_method)) {
  cat("  # Different scale sizes - recode to common scale\n")
  for (src in sources) {
    wave <- src$wave
    cat(sprintf("  %s_harmonized <- %s_numeric  # TODO: implement recode logic\n", wave, wave))
  }
}

cat("\n  # Combine into single harmonized variable\n")
cat("  harmonized <- bind_rows(\n")
for (i in seq_along(sources)) {
  wave <- sources[[i]]$wave
  cat(sprintf("    %s |> mutate(__%s_%s_harmonized = %s_harmonized),\n", wave, var_name, wave, wave))
}
cat("  ) |>\n")
cat(sprintf("    select(all_of(c('%s'))) |>\n", paste(sapply(sources, function(x) sprintf("__%s_%s_harmonized", var_name, x$wave)), collapse = "', '")))
cat(sprintf("    rename(%s = __%s_%s_harmonized) |>\n", var_name, var_name, sources[[1]]$wave))
cat("    as_vector()\n")
cat("\n  return(harmonized)\n")
cat("}\n\n")

cat("# Apply harmonization\n")
cat(sprintf("data_harmonized <- waves |>\n"))
cat(sprintf("  bind_rows(.id = 'wave') |>\n"))
cat(sprintf("  mutate(%s = harmonize_%s(waves))\n\n", var_name, var_name))

cat("# ============================================================================\n")
cat("# QUALITY CONTROL\n")
cat("# ============================================================================\n\n")

cat("# Check data quality\n")
cat(sprintf("cat('\\nVariable: %s\\n')\n", var_name))
cat(sprintf("cat('N observations: ', nrow(data_harmonized), '\\n')\n"))
cat(sprintf("cat('Valid values: ', sum(!is.na(data_harmonized$%s)), '\\n')\n", var_name))
cat(sprintf("cat('Missing values: ', sum(is.na(data_harmonized$%s)), '\\n')\n", var_name))
cat(sprintf("cat('Range: ', min(data_harmonized$%s, na.rm=TRUE), ' to ', max(data_harmonized$%s, na.rm=TRUE), '\\n')\n", var_name, var_name))
cat(sprintf("cat('Scale distribution:\\n')\n"))
cat(sprintf("print(table(data_harmonized$%s, useNA = 'always'))\n", var_name))

cat("\ncat('\\n✅ Harmonization complete!\\n')\n")

cat("\n# ============================================================================\n")
cat("# END HARMONIZATION\n")
cat("# ============================================================================\n")

cat("\n\n=== KEY DECISIONS NEEDED ===\n\n")
cat("1. VERIFY HARMONIZATION METHOD\n")
cat(sprintf("   Current setting: %s\n", harmonize_method))
cat("   Options:\n")
cat("   - direct: Use if all waves use 1-4 scale with same orientation\n")
cat("   - safe_reverse_4pt: Use if some waves have 4→1, 1→4 (reversed scale)\n")
cat("   - safe_reverse_5pt: Use if some waves use 1-5 instead of 1-4\n")
cat("   - recode_to_4pt: Use if different scale sizes across waves\n\n")

cat("2. VERIFY SCALE BOUNDS\n")
cat(sprintf("   Current: min=%d, max=%d\n", scale_min, scale_max))
cat("   Action: Review actual data to confirm\n\n")

cat("3. HANDLE REVERSALS\n")
if (reversed) {
  cat("   FLAGGED AS POTENTIALLY REVERSED\n")
  cat("   Action: Check individual wave labels to confirm direction\n")
} else {
  cat("   Not flagged for reversal\n")
  cat("   Action: Still verify by comparing question labels across waves\n")
}

cat("\n")
