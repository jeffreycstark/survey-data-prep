#!/usr/bin/env Rscript

# Explore institutional trust variables across waves
# Shows raw q7-q20 data to understand institution grouping

library(dplyr)
source(here::here("src", "r", "utils", "load_data.R"))

cat("\n=== LOADING SURVEY WAVES ===\n")
waves <- load_survey_waves()

cat("\n=== EXTRACTING INSTITUTIONAL TRUST VARIABLES (q7-q20) ===\n")
inst_data <- extract_institutional_trust(
  waves$w1, waves$w2, waves$w3, 
  waves$w4, waves$w5, waves$w6,
  q_min = 7, q_max = 20
)

cat("\n=== RAW INSTITUTIONAL TRUST DATA ===\n")
cat(sprintf("Total variables found: %d\n\n", nrow(inst_data)))

# Display in readable format
for (i in 1:nrow(inst_data)) {
  row <- inst_data[i, ]
  cat(sprintf("%-3s | %-8s | %s\n", 
              row$wave, 
              row$variable_name, 
              row$variable_label))
}

cat("\n=== BY WAVE SUMMARY ===\n")
wave_summary <- inst_data %>%
  group_by(wave) %>%
  summarise(n_institutions = n(), .groups = "drop") %>%
  arrange(wave)
print(wave_summary)

cat("\n=== INSTITUTIONS BY WAVE ===\n")
inst_by_wave <- inst_data %>%
  select(wave, variable_name, variable_label) %>%
  arrange(wave, variable_name)
print(inst_by_wave)

cat("\n=== SAVE DETAILED VIEW ===\n")
# Save to file for easier review
write.csv(inst_data[, c("wave", "variable_name", "variable_label")],
          here::here("outputs", "institutional_trust_raw.csv"),
          row.names = FALSE)
cat("✅ Saved to: outputs/institutional_trust_raw.csv\n")

cat("\n=== NEXT STEPS ===\n")
cat("1. Review the output above to identify institutions\n")
cat("2. Note which institutions appear in which waves\n")
cat("3. Identify reversed scales or institution variations\n")
cat("4. Manually group into separate YAML entries by institution\n\n")
