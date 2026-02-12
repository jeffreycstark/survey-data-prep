# R/utils/_load_functions.R
# Load all custom utility functions

source(here::here("src", "r", "utils", "recoding.R"))
source(here::here("src", "r", "utils", "validation.R"))
source(here::here("src", "r", "utils", "helpers.R"))
source(here::here("src", "r", "utils", "composites.R"))
source(here::here("src", "r", "utils", "clear_env.R"))
source(here::here("src", "r", "utils", "data_prep_helpers.R"))
# Note: lint.R is NOT sourced here - it's a standalone script meant to be run manually

cat("\n=== Custom Functions Loaded ===\n")
cat("Available functions:\n")
cat("  Recoding:\n")
cat("    - safe_reverse_3pt(), safe_reverse_4pt(), safe_reverse_5pt(), safe_reverse_6pt()\n")
cat("    - safe_3pt_none(), safe_4pt_none(), safe_5pt_none(), safe_6pt_none()\n")
cat("    - safe_6pt_to_4pt(), recode_has_party()\n")
cat("    - middle_identity_5pt(), middle_reverse_5pt()\n")
cat("    - safe_reverse_2pt(), collapse_6pt_to_4pt_reverse()\n")
cat("    - recode_w1_trust_binary(), recode_w5_trust_binary()\n")
cat("    - recode_w2_anticorrupt(), recode_w3_witnessed(), recode_w4_witnessed()\n")
cat("    - recode_w6_country(), recode_w6_corruption()\n")
cat("  Validation:\n")
cat("    - check_unexpected_values(), validate_range()\n")
cat("  Data Prep Helpers:\n")
cat("    - create_validated_composite(), report_missing()\n")
cat("    - verify_recoding(), batch_clean_missing()\n")
cat("    - normalize_0_1(), standardize_z(), describe_by_country()\n")
cat("==============================\n\n")


