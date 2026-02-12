#!/usr/bin/env Rscript

# Generate clean YAML entries for 13 core institutional trust measures
# This version properly consolidates institution variations

library(dplyr)
library(stringr)
library(here)

source(here::here("src", "r", "utils", "load_data.R"))

cat("\n=== INSTITUTIONAL TRUST YAML GENERATION (v2 - Consolidated) ===\n")

# 1. Load data
cat("\nLoading survey waves...\n")
waves <- load_survey_waves()

# 2. Extract institutional trust variables
cat("Extracting institutional trust variables...\n")
inst_data <- extract_institutional_trust(
  waves$w1, waves$w2, waves$w3,
  waves$w4, waves$w5, waves$w6,
  q_min = 7, q_max = 20
)

# 3. Parse institution names from labels
cat("Parsing institution names...\n")
extract_institution_name <- function(labels) {
  labels %>%
    tolower() %>%
    str_trim() %>%
    # Remove common question prefixes and text
    str_replace_all("^.*?trust.*?in the ", "") %>%
    str_replace_all("^.*?trust in ", "") %>%
    str_replace_all("^.*?trust ", "") %>%
    str_replace_all("how much trust do you have in ", "") %>%
    str_replace_all("\\?.*$", "") %>%
    str_replace_all("<.*>", "") %>%
    str_replace_all("\\[.*\\]", "") %>%
    str_replace_all("\\(.*\\)", "") %>%
    str_replace_all(" or .*", "") %>%
    str_replace_all("\\s+", " ") %>%
    str_trim()
}

inst_data$institution_raw <- extract_institution_name(inst_data$variable_label)

# 4. Define core 13 institutions with mapping rules
core_institutions_map <- list(
  "president" = c("president", "executive office", "executive", "prime minister"),
  "courts" = c("courts", "court"),
  "national_government" = c("national government"),
  "political_parties" = c("political parties", "political party", "parties"),
  "parliament" = c("parliament"),
  "civil_service" = c("civil service", "civil"),
  "military" = c("military", "armed forces", "armed force"),
  "police" = c("police"),
  "local_government" = c("local government"),
  "newspapers" = c("newspapers", "newspaper"),
  "television" = c("television", "tv"),
  "election_commission" = c("election commission"),
  "ngos" = c("ngos", "non-governmental organizations", "non-governmental", "ngo")
)

# 5. Map raw institutions to core institutions
map_institution <- function(raw_inst) {
  raw_inst <- tolower(str_trim(raw_inst))

  for (core_name in names(core_institutions_map)) {
    patterns <- core_institutions_map[[core_name]]
    if (any(sapply(patterns, function(p) str_detect(raw_inst, fixed(p, ignore_case = TRUE))))) {
      return(core_name)
    }
  }
  return(NA_character_)
}

inst_data$institution <- sapply(inst_data$institution_raw, map_institution)

# 6. Filter to mapped institutions only
inst_core <- inst_data %>%
  filter(!is.na(institution)) %>%
  arrange(institution, wave)

cat(sprintf("\n✅ Successfully mapped %d of %d institutional trust variables to core 13\n",
            nrow(inst_core), nrow(inst_data)))

# Show summary
cat("\n=== INSTITUTIONS FOUND ===\n")
inst_summary <- inst_core %>%
  group_by(institution) %>%
  summarise(n = n(), waves = paste(unique(wave), collapse = ", "), .groups = "drop") %>%
  arrange(institution)
print(inst_summary)

# Show unmapped institutions
unmapped <- inst_data %>% filter(is.na(institution))
if (nrow(unmapped) > 0) {
  cat("\n=== UNMAPPED INSTITUTIONS ===\n")
  cat("These were excluded because they don't match the core 13:\n")
  for (i in 1:min(nrow(unmapped), 10)) {
    cat(sprintf("  - %s (%s, %s)\n",
                unmapped$institution_raw[i],
                unmapped$variable_name[i],
                unmapped$wave[i]))
  }
  if (nrow(unmapped) > 10) {
    cat(sprintf("  ... and %d more\n", nrow(unmapped) - 10))
  }
}

# 7. Generate simple YAML for each core institution
cat("\n=== GENERATING YAML FILES ===\n")
output_dir <- here::here("src", "config", "harmonize")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Clean up old files first
old_files <- list.files(output_dir, pattern = "^trust_.*\\.yml$", full.names = TRUE)
if (length(old_files) > 0) {
  file.remove(old_files)
  cat("Cleaned up previous YAML files\n")
}

generate_yaml_template <- function(data, institution_name) {
  # Create a clean YAML template for institutional trust

  # Make a human-readable institution label
  label_name <- str_replace_all(institution_name, "_", " ") %>%
    str_to_title()

  yaml_lines <- c(
    "# Institutional Trust YAML Template",
    sprintf("# Institution: %s", label_name),
    "# Auto-generated from institutional trust codebook extraction",
    "",
    "variables:",
    sprintf("  - name: trust_%s", institution_name),
    sprintf("    id: TRUST_%s  # FILL IN with appropriate identifier", toupper(institution_name)),
    sprintf("    label: Trust in %s", label_name),
    "    concept: institutional_trust",
    "    type: ordinal",
    ""
  )

  # Add wave-specific mappings
  yaml_lines <- c(yaml_lines, "    sources:")

  for (i in seq_len(nrow(data))) {
    row <- data[i, ]
    yaml_lines <- c(yaml_lines,
                    sprintf("      - wave: %s", row$wave),
                    sprintf("        variable: %s", row$variable_name),
                    sprintf("        label: '%s'", row$variable_label))
  }

  yaml_lines <- c(yaml_lines, "",
                  "    # Scale information - REVIEW AND CONFIRM",
                  "    scale:",
                  "      type: likert",
                  "      min_value: 1",
                  "      max_value: 4  # CONFIRM: may be 1-4, 1-5, or other",
                  "      reversed: false  # IMPORTANT: Check if some waves are reversed",
                  "",
                  "    # Harmonization method - SELECT APPROPRIATE METHOD",
                  "    harmonize:",
                  "      - method: direct  # Use if all scales are identical",
                  "      # - method: safe_reverse_4pt  # Uncomment if reversed scales detected",
                  "      # - method: recode_to_4pt    # Uncomment for scale conversion",
                  "",
                  "    # Quality control bounds",
                  "    bounds:",
                  "      min_value: 1",
                  "      max_value: 4"
                  )

  return(paste(yaml_lines, collapse = "\n"))
}

# Generate YAML for each institution
file_count <- 0
for (inst in inst_summary$institution) {

  tryCatch({
    # Get data for this institution
    inst_rows <- inst_core %>% filter(institution == inst)

    # Create YAML filename
    yaml_filename <- file.path(output_dir, sprintf("trust_%s.yml", inst))

    # Generate YAML
    yaml_str <- generate_yaml_template(inst_rows, inst)

    # Save
    writeLines(yaml_str, yaml_filename)
    file_count <- file_count + 1
    cat(sprintf("✅ Saved: trust_%s.yml (%d sources across %s)\n",
                inst, nrow(inst_rows),
                paste(unique(inst_rows$wave), collapse = ", ")))

  }, error = function(e) {
    cat(sprintf("❌ Error generating YAML for %s: %s\n", inst, e$message))
  })
}

cat(sprintf("\n✅ Generated %d YAML files\n", file_count))

# List generated files
cat("\n=== YAML FILES CREATED ===\n")
yaml_files <- list.files(output_dir, pattern = "^trust_.*\\.yml$", full.names = FALSE)
for (f in sort(yaml_files)) {
  cat(sprintf("  - %s\n", f))
}

cat("\n=== NEXT STEPS ===\n")
cat("1. Review each YAML file in src/config/harmonize/trust_*.yml\n")
cat("2. Verify scale information (min/max values, reversed flags)\n")
cat("3. Fill in 'id' fields with appropriate identifiers\n")
cat("4. Select appropriate 'harmonize' method for each institution\n")
cat("5. Run: /harmonize-variables to execute harmonization\n\n")
