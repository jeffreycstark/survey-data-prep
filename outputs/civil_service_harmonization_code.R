# ============================================================================
# HARMONIZED VARIABLE: trust_civil_service
# ============================================================================
# Variable ID: TRUST_CIVIL_SERVICE
# Label: Trust in Civil Service
# Concept: institutional_trust
# Type: ordinal
# 
# Method: direct (no transformation needed - all waves use identical scale)
# Scale: Likert (1-4)
# Reversed: FALSE
#
# ============================================================================
# SOURCE MAPPING (6 waves)
# ============================================================================
#
# Wave 1: q011 "How much trust do you have in civil service?"
# Wave 2: q12  "Trust in Civil service"
# Wave 3: q12  "q12. Civil service"
# Wave 4: q12  "12 Civil service"
# Wave 5: q12  "12 Civil service"
# Wave 6: q12  "12 Civil Service"
#
# ============================================================================

library(dplyr)
library(here)

# Step 1: Load raw survey waves
# ============================================================================
waves <- list(
  w1 = readRDS(here::here('data', 'processed', 'w1.rds')),
  w2 = readRDS(here::here('data', 'processed', 'w2.rds')),
  w3 = readRDS(here::here('data', 'processed', 'w3.rds')),
  w4 = readRDS(here::here('data', 'processed', 'w4.rds')),
  w5 = readRDS(here::here('data', 'processed', 'w5.rds')),
  w6 = readRDS(here::here('data', 'processed', 'w6.rds')),
)

# Step 2: Define harmonization function
# ============================================================================
harmonize_trust_civil_service <- function(waves) {
  
  # Extract source variables from each wave
  # (handles different question numbers across waves)
  w1_raw <- waves$w1$q011
  w2_raw <- waves$w2$q12
  w3_raw <- waves$w3$q12
  w4_raw <- waves$w4$q12
  w5_raw <- waves$w5$q12
  w6_raw <- waves$w6$q12
  
  # Convert to numeric (handles labelled SPSS data from haven)
  w1_numeric <- as.numeric(w1_raw)
  w2_numeric <- as.numeric(w2_raw)
  w3_numeric <- as.numeric(w3_raw)
  w4_numeric <- as.numeric(w4_raw)
  w5_numeric <- as.numeric(w5_raw)
  w6_numeric <- as.numeric(w6_raw)
  
  # Apply harmonization method: "direct"
  # All waves use identical 1-4 Likert scale with same orientation
  # No transformation or recoding needed
  w1_harmonized <- w1_numeric
  w2_harmonized <- w2_numeric
  w3_harmonized <- w3_numeric
  w4_harmonized <- w4_numeric
  w5_harmonized <- w5_numeric
  w6_harmonized <- w6_numeric
  
  # Return list of harmonized vectors, one per wave
  list(
    w1 = w1_harmonized,
    w2 = w2_harmonized,
    w3 = w3_harmonized,
    w4 = w4_harmonized,
    w5 = w5_harmonized,
    w6 = w6_harmonized
  )
}

# Step 3: Apply harmonization
# ============================================================================
harmonized <- harmonize_trust_civil_service(waves)

# Step 4: Combine waves and add harmonized variable
# ============================================================================
data_harmonized <- bind_rows(
  waves$w1 |> mutate(wave = "w1", trust_civil_service = harmonized$w1),
  waves$w2 |> mutate(wave = "w2", trust_civil_service = harmonized$w2),
  waves$w3 |> mutate(wave = "w3", trust_civil_service = harmonized$w3),
  waves$w4 |> mutate(wave = "w4", trust_civil_service = harmonized$w4),
  waves$w5 |> mutate(wave = "w5", trust_civil_service = harmonized$w5),
  waves$w6 |> mutate(wave = "w6", trust_civil_service = harmonized$w6)
)

# Step 5: Quality Control
# ============================================================================
cat("\n=== HARMONIZATION QUALITY REPORT ===\n")
cat("Variable: trust_civil_service\n")
cat("N observations:", nrow(data_harmonized), "\n")
cat("Valid values:", sum(!is.na(data_harmonized$trust_civil_service)), "\n")
cat("Missing values:", sum(is.na(data_harmonized$trust_civil_service)), "\n")
cat("Percentage complete:", 
    round(100 * sum(!is.na(data_harmonized$trust_civil_service)) / nrow(data_harmonized), 1), 
    "%\n\n")

cat("Range:", 
    min(data_harmonized$trust_civil_service, na.rm = TRUE), 
    "to", 
    max(data_harmonized$trust_civil_service, na.rm = TRUE), "\n\n")

cat("Scale Distribution (all waves combined):\n")
print(table(data_harmonized$trust_civil_service, useNA = "always"))

cat("\nDistribution by wave:\n")
print(data_harmonized |> 
      group_by(wave) |>
      summarise(
        n = n(),
        valid = sum(!is.na(trust_civil_service)),
        missing = sum(is.na(trust_civil_service)),
        mean = mean(trust_civil_service, na.rm = TRUE),
        .groups = "drop"
      ))

cat("\n✅ Harmonization complete!\n")

# ============================================================================
# END HARMONIZATION
# ============================================================================
