# src/r/codebook/example_satisfaction_democracy.R
# Real example: Satisfaction & Democracy questions across waves
# Using actual search results from your data

# Load module
source("src/r/codebook/codebook_workflow.R")

# ==============================================================================
# REAL DATA: Search results for "satisf" containing "democracy"
# ==============================================================================

# Create data frame from the raw search output
# Manually mapping the file names to wave numbers:
# Wave1_20170906.sav → w1
# Wave2_20250609.sav → w2
# ABS3 merge20250609.sav → w3
# W4_v15_merged20250609_release.sav → w4
# 20230505_W5_merge_15.sav → w5
# W6_Cambodia_Release_20240819.sav → w6

search_results <- data.frame(
  wave = c(
    "w1", "w1",
    "w2", "w2", "w2",
    "w3", "w3", "w3",
    "w4", "w4", "w4",
    "w5", "w5",
    "w6", "w6", "w6"
  ),
  variable_name = c(
    "q098", "q104",
    "q93", "q99", "se9a",
    "q89", "q95", "se13a",
    "q92", "q98", "se14a",
    "q99", "q105",
    "q90", "q96", "SE14a"
  ),
  variable_label = c(
    "Satisfaction with the way democracy works in our country?",
    "How satisfied or dissatisfied are you with the current government?",
    "On the whole, how satisfied or dissatisfied are you with the way democracy works in [country]?",
    "How satisfied or dissatisfied are you with the [name of present] government?",
    "Does the total income of your household allow you to satisfactorily cover your needs?",
    "On the whole, how satisfied or dissatisfied are you with the way democracy works in [Country]?",
    "How satisfied or dissatisfied are you with the [name of president, etc. ruling current] government?",
    "Does the total income of your household allow you to satisfactorily cover your needs?",
    "On the whole, how satisfied or dissatisfied are you with the way democracy works in the country?",
    "How satisfied or dissatisfied are you with the current government?",
    "Does the total income of your household allow you to satisfactorily cover your needs?",
    "On the whole, how satisfied or dissatisfied are you with the way democracy works in our country?",
    "How satisfied or dissatisfied are you with the current president/government?",
    "On the whole, how satisfied or dissatisfied are you with the way democracy works in the country?",
    "How satisfied or dissatisfied are you with the current president/government?",
    "Does the total income of your household allow you to satisfactorily cover your needs?"
  ),
  value_labels = list(
    # W1 q098: Democracy satisfaction
    c("1" = "Not at all satisfied", "2" = "Not very satisfied", "3" = "Fairly satisfied", "4" = "Very satisfied"),
    # W1 q104: Government satisfaction (note: has 5 values with "Half and Half")
    c("1" = "Very dissatisfied", "2" = "Somewhat dissatisfied", "3" = "Somewhat satisfied", "4" = "Very satisfied", "5" = "Half and Half"),
    # W2 q93: Democracy satisfaction
    c("1" = "Not at all satisfied", "2" = "Not very satisfied", "3" = "Fairly satisfied", "4" = "Very satisfied"),
    # W2 q99: Government satisfaction (REVERSED: 1=Very satisfied, 4=Very dissatisfied)
    c("1" = "Very satisfied", "2" = "Somewhat satisfied", "3" = "Somewhat dissatisfied", "4" = "Very dissatisfied"),
    # W2 se9a: Household income satisfaction
    c("1" = "Covers the needs well, we can save", "2" = "Covers the needs all right, without much difficulty", "3" = "Does not cover the needs, there are difficulties", "4" = "Does not cover the needs, there are great difficulties"),
    # W3 q89: Democracy satisfaction (REVERSED: 1=Very satisfied, 4=Not at all satisfied)
    c("1" = "Very satisfied", "2" = "Fairly satisfied", "3" = "Not very satisfied", "4" = "Not at all satisfied"),
    # W3 q95: Government satisfaction
    c("1" = "Very satisfied", "2" = "Somewhat satisfied", "3" = "Somewhat dissatisfied", "4" = "Very dissatisfied"),
    # W3 se13a: Household income satisfaction
    c("1" = "Our income covers the needs well, we can save", "2" = "Our income covers the needs all right, without much difficulty", "3" = "Our income does not cover the needs, there are difficulties", "4" = "Our income does not cover the needs, there are great difficulties"),
    # W4 q92: Democracy satisfaction (1=Very satisfied, 4=Not at all satisfied)
    c("1" = "Very satisfied", "2" = "Fairly satisfied", "3" = "Not very satisfied", "4" = "Not at all satisfied"),
    # W4 q98: Government satisfaction
    c("1" = "Very satisfied", "2" = "Somewhat satisfied", "3" = "Somewhat dissatisfied", "4" = "Very dissatisfied"),
    # W4 se14a: Household income satisfaction
    c("1" = "Our income covers the needs well, we can save", "2" = "Our income covers the needs all right, without much difficulties", "3" = "Our income does not cover the needs, there are difficulties", "4" = "Our income does not cover the needs, there are great difficulties"),
    # W5 q99: Democracy satisfaction (1=Very satisfied, 4=Not at all satisfied)
    c("1" = "Very satisfied", "2" = "Fairly satisfied", "3" = "Not very satisfied", "4" = "Not at all satisfied"),
    # W5 q105: Government satisfaction
    c("1" = "Very satisfied", "2" = "Somewhat satisfied", "3" = "Somewhat dissatisfied", "4" = "Very dissatisfied"),
    # W6 q90: Democracy satisfaction (1=Very satisfied, 4=Not at all satisfied)
    c("1" = "Very satisfied", "2" = "Fairly satisfied", "3" = "Not very satisfied", "4" = "Not at all satisfied"),
    # W6 q96: Government satisfaction
    c("1" = "Very satisfied", "2" = "Somewhat satisfied", "3" = "Somewhat dissatisfied", "4" = "Very dissatisfied"),
    # W6 SE14a: Household income satisfaction (5pt scale)
    c("1" = "Our income covers the needs well, we can save a lot", "2" = "Our income covers the needs well, we can save", "3" = "Our income covers the needs all right, without much difficulty", "4" = "Our income does not cover the needs, there are difficulties", "5" = "Our income does not cover the needs, there are great difficulties")
  ),
  stringsAsFactors = FALSE
)

# ==============================================================================
# ANALYSIS: Review what was found
# ==============================================================================

cat("\n=== SEARCH RESULTS SUMMARY ===\n")
cat(sprintf("Total matches: %d\n", nrow(search_results)))
cat(sprintf("Waves: %s\n", paste(unique(search_results$wave), collapse = ", ")))
cat(sprintf("Variables: %s\n\n", paste(unique(search_results$variable_name), collapse = ", ")))

# Show analysis report
cat("\n=== DETAILED ANALYSIS REPORT ===\n\n")
report <- analyze_search_results(search_results, concept = "democracy_satisfaction")
cat(report)

# ==============================================================================
# GENERATION: Create YAML templates grouped by question
# ==============================================================================

cat("\n\n=== GENERATING YAML TEMPLATES ===\n\n")

# Generate YAML (this will group by question and detect reversals)
yaml_str <- generate_codebook_yaml(search_results, concept = "democracy_satisfaction")

cat(yaml_str)

# ==============================================================================
# SAVE YAML
# ==============================================================================

cat("\n\n=== SAVING TO FILE ===\n")
output_file <- "src/config/harmonize/democracy_satisfaction.yml"
writeLines(yaml_str, output_file)
cat(sprintf("✅ YAML template saved to: %s\n", output_file))
cat("\nNext steps:\n")
cat("1. Review the YAML file\n")
cat("2. Fill in the 'id' field for each question\n")
cat("3. Confirm harmonization methods (especially reversals)\n")
cat("4. Use with /harmonize-variables skill\n")
