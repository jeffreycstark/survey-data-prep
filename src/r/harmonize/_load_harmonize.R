# src/r/harmonize/_load_harmonize.R
# Loader for all harmonization functions

# Load core harmonization engine
source(here::here("src/r/harmonize/harmonize.R"))

# Load validation functions
source(here::here("src/r/harmonize/validate_spec.R"))

# Load reporting functions
source(here::here("src/r/harmonize/report_harmonization.R"))

# Message user
message("✓ Harmonization functions loaded:")
message("  - harmonize_variable()")
message("  - harmonize_all()")
message("  - validate_harmonize_spec()")
message("  - check_recoding_functions()")
message("  - report_harmonization()")
message("  - harmonization_summary()")
message("  - check_harmonization_bounds()")
