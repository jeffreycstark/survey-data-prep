#!/usr/bin/env Rscript

# Generate YAML entries for 13 core institutional trust measures
# Groups institutions across waves and handles variations

library(dplyr)
library(stringr)
library(here)

source(here::here("src", "r", "utils", "load_data.R"))
source(here::here("src", "r", "codebook", "codebook_analysis.R"))
source(here::here("src", "r", "codebook", "codebook_workflow.R"))

# Extract institution name from question label
extract_institution_name <- function(labels) {
  labels %>%
    tolower() %>%
    str_trim() %>%
    # Remove common question prefixes
    str_replace_all("^.*trust (in|the) ", "") %>%
    str_replace_all("^.*in the ", "") %>%
    str_replace_all("\\?.*$", "") %>%
    str_replace_all("<.*>", "") %>%
    str_replace_all("\\[.*\\]", "") %>%
    str_trim() %>%
    # Handle specific cases
    str_replace_all("how much trust do you have in ", "") %>%
    str_replace_all("trust in ", "") %>%
    str_replace_all(" or .*$", "") %>%
    str_trim()
}

cat("\n=== GENERATING INSTITUTIONAL TRUST YAML ===\n")

# 1. Load data
cat("\nLoading survey waves...\n")
waves <- load_survey_waves()

# 2. Extract institutional trust variables
cat("\nExtracting institutional trust variables...\n")
inst_data <- extract_institutional_trust(
  waves$w1, waves$w2, waves$w3, 
  waves$w4, waves$w5, waves$w6,
  q_min = 7, q_max = 20
)

# 3. Parse institution names from labels
cat("Parsing institution names...\n")
inst_data$institution <- extract_institution_name(inst_data$variable_label)

# 4. Filter to core 13 institutions (exclude membership, other specify, extras)
core_institutions <- c(
  "president", "executive", "prime minister",
  "courts", "court",
  "national government", "government",
  "political parties", "parties",
  "parliament",
  "civil service", "civil",
  "military", "armed forces",
  "police",
  "local government",
  "newspapers", "newspaper",
  "television", "tv",
  "election commission",
  "ngos", "non-governmental"
)

inst_data$is_core <- sapply(inst_data$institution, function(x) {
  any(str_detect(tolower(x), paste(core_institutions, collapse = "|")))
})

cat(sprintf("\nTotal variables: %d\n", nrow(inst_data)))
cat(sprintf("Core institutional trust: %d\n", sum(inst_data$is_core)))
cat(sprintf("Other variables: %d\n", sum(!inst_data$is_core)))

# Show excluded items
cat("\nExcluded variables:\n")
excluded <- inst_data %>% filter(!is_core) %>% select(wave, variable_name, variable_label)
if (nrow(excluded) > 0) {
  for (i in 1:nrow(excluded)) {
    cat(sprintf("  %s | %-12s | %s\n", 
                excluded$wave[i], 
                excluded$variable_name[i], 
                substr(excluded$variable_label[i], 1, 60)))
  }
}

# 5. Keep only core institutions
inst_core <- inst_data %>% filter(is_core)

# 6. Clean up institution names for grouping
normalize_institution <- function(x) {
  x <- tolower(x)
  x <- str_trim(x)
  # Standardize names
  x <- str_replace_all(x, "prime minister.*", "president")
  x <- str_replace_all(x, "executive.*", "president")
  x <- str_replace_all(x, "court", "courts")
  x <- str_replace_all(x, "national government.*", "national_government")
  x <- str_replace_all(x, "^government.*", "national_government")
  x <- str_replace_all(x, "political parties|parties", "political_parties")
  x <- str_replace_all(x, "civil service|civil", "civil_service")
  x <- str_replace_all(x, "military|armed forces", "military")
  x <- str_replace_all(x, "police", "police")
  x <- str_replace_all(x, "local government", "local_government")
  x <- str_replace_all(x, "newspaper", "media_newspapers")
  x <- str_replace_all(x, "television|tv", "media_television")
  x <- str_replace_all(x, "election commission", "election_commission")
  x <- str_replace_all(x, "ngos|non-governmental", "ngos")
  x <- str_replace_all(x, "\\s+", "_")
  x
}

inst_core$institution_std <- normalize_institution(inst_core$institution)

# 7. Group by institution
cat("\n=== INSTITUTIONS FOUND ===\n")
inst_groups <- inst_core %>% 
  group_by(institution_std) %>%
  summarise(n = n(), waves = paste(unique(wave), collapse = ", "), .groups = "drop") %>%
  arrange(institution_std)

print(inst_groups)

# 8. Generate YAML for each institution
cat("\n=== GENERATING YAML FILES ===\n")
output_dir <- here::here("src", "config", "harmonize")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

generate_simple_yaml <- function(data, concept_name) {
  # Create a simple YAML template for institutional trust
  # Data should have: wave, variable_name, variable_label, institution_std

  yaml_lines <- c(
    sprintf("# Institutional Trust: %s", data$institution_std[1]),
    "# Auto-generated from institutional trust codebook extraction",
    "",
    "variables:",
    sprintf("  - name: trust_%s", tolower(gsub(" ", "_", data$institution_std[1]))),
    "    id: trust_[INSTITUTION_ID]  # FILL IN",
    "    label: Trust in [INSTITUTION]  # FILL IN",
    "    concept: institutional_trust",
    ""
  )

  # Add wave-specific mappings
  yaml_lines <- c(yaml_lines, "    sources:")

  for (i in seq_len(nrow(data))) {
    row <- data[i, ]
    yaml_lines <- c(yaml_lines,
                    sprintf("      - wave: %s", row$wave),
                    sprintf("        variable: %s", row$variable_name),
                    sprintf("        label: %s", row$variable_label))
  }

  yaml_lines <- c(yaml_lines, "",
                  "    # Auto-detected scale - REVIEW AND CONFIRM",
                  "    scale:",
                  "      type: likert  # CONFIRM (1-4, 1-5, etc.)",
                  "      min_value: 1",
                  "      max_value: 4",
                  "      reversed: false  # REVIEW FOR REVERSALS",
                  "",
                  "    # Harmonization method - SELECT ONE",
                  "    harmonize:",
                  "      - method: direct  # Use if scales are identical",
                  "      # - method: safe_reverse_4pt  # Use if scale is reversed",
                  "      # - method: recode_to_4pt    # Use if different scale size",
                  "",
                  "    # Quality control bounds",
                  "    bounds:",
                  "      min_value: 1",
                  "      max_value: 4"
                  )

  return(paste(yaml_lines, collapse = "\n"))
}

# Try to generate YAML, handle errors gracefully
for (inst in inst_groups$institution_std) {

  tryCatch({
    # Get data for this institution
    inst_rows <- inst_core %>% filter(institution_std == inst)

    # Create YAML filename
    yaml_filename <- file.path(output_dir, paste0("trust_", inst, ".yml"))

    # Try complex YAML first, fall back to simple version if it fails
    yaml_str <- tryCatch(
      generate_codebook_yaml(inst_rows, concept = paste0("trust_", inst)),
      error = function(e) {
        cat(sprintf("  (using simplified template for: %s)\n", inst))
        generate_simple_yaml(inst_rows, paste0("trust_", inst))
      }
    )

    # Save
    writeLines(yaml_str, yaml_filename)
    cat(sprintf("✅ Saved: trust_%s.yml (%d waves)\n", inst, nrow(inst_rows)))

  }, error = function(e) {
    cat(sprintf("❌ Error generating YAML for %s: %s\n", inst, e$message))
  })
}

cat("\n=== YAML FILES CREATED ===\n")
yaml_files <- list.files(output_dir, pattern = "^trust_.*\\.yml$", full.names = FALSE)
for (f in sort(yaml_files)) {
  cat(sprintf("  - %s\n", f))
}

cat("\n=== NEXT STEPS ===\n")
cat("1. Review the YAML files in src/config/harmonize/trust_*.yml\n")
cat("2. Check scale detection and reversal flags\n")
cat("3. Fill in 'id' fields\n")
cat("4. Confirm 'harmonize' methods (add safe_reverse_*pt if needed)\n")
cat("5. Run harmonization\n\n")
