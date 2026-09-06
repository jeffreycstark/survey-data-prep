## ============================================================================
## run_kgss_prospector.R
## Run slope_prospector on KGSS harmonized data (Korea, 2003-2025)
##
## Output: outputs/prospecting/kgss/
##
## NOTE: KGSS is single-country (KOR). Country clustering is disabled.
## Wave = calendar year (2003-2025); slopes are expressed per year.
## ============================================================================

library(here)
library(tidyverse)

# ── 1. LOAD HARMONIZED KGSS DATA ──────────────────────────────────────────────

cat("Loading KGSS harmonized data...\n")
d <- readRDS(here("data", "processed", "kgss_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, years %s\n",
            format(nrow(d), big.mark = ","), ncol(d),
            paste(sort(unique(d$wave)), collapse = ", ")))

# ── 2. SELECT VARIABLES FOR ANALYSIS ─────────────────────────────────────────

# Exclude system/identifier/weight variables
system_vars <- c("wave", "country", "row_id", "weight",
                 "resp_id", "yr_resp_id", "questionnaire_form")

# Exclude nominal/categorical variables that are not ordinal scales.
# A slope fitted to a nominal code is meaningless: it measures nothing but drift
# in how the codes happen to be distributed. Before this list was extended, four
# of them (region, sex, marital_status, employment) sat in the TOP TWENTY
# "significant structural breaks" for KGSS.
nominal_vars <- c(
  "party_id",         # nominal, wave-incompatible party codes
  "party_pref",       # nominal, wave-incompatible party codes
  "ineq_success_factor",  # 3-category forced choice (hard work / luck / equal), not ordinal
  "region",           # 1=Seoul ... 7=Jeju — pure nominal geography
  "religion",         # 1=Buddhist, 2=Protestant, ... — nominal denomination
  "marital_status",   # 1=married ... 6=cohabiting — nominal
  "employment",       # 1=employed / 2=not employed — sample composition, not an attitude
  "sex"               # 1=male / 2=female — a slope here is the sample sex ratio
)

# Excluded for coding traps rather than for being nominal:
#   education        — KGSS code 8 is "other", NOT a level above PhD (0=none ... 7=PhD,
#                      8=other). Min-max normalizing the raw ladder ranks "other" top.
#                      See CLAUDE.md, "Education: use education_5cat, never
#                      education_level_01". education_5cat is kept and is correct.
#   education_5cat_01 — a linear rescale of education_5cat (r = 1.00). Keeping both
#                      double-counts education in every distribution the prospector
#                      builds and guarantees a trivial "divergent pair" of one
#                      variable with itself.
trap_vars <- c("education", "education_5cat_01")

# Exclude binary electoral participation (1=voted, 2=did not)
# These are binary indicators, not meaningful scales for slope analysis
binary_vars <- c("voted_presidential", "voted_general", "voted_local")

exclude <- c(system_vars, nominal_vars, binary_vars, trap_vars)

numeric_vars <- names(d)[sapply(d, is.numeric)]
candidate_vars <- setdiff(numeric_vars, exclude)

# Drop any vars with implausibly large values (catches raw codes that slipped through)
var_maxabs <- sapply(candidate_vars, function(v) max(abs(d[[v]]), na.rm = TRUE))
vars <- candidate_vars[var_maxabs <= 100]

cat(sprintf("  Variables included in analysis: %d\n", length(vars)))

# ── 3. COMPUTE YEAR MEANS (single country = KOR) ─────────────────────────────

cat("Computing year means...\n")
means_long <- d %>%
  select(country, wave, all_of(vars)) %>%
  pivot_longer(
    cols      = all_of(vars),
    names_to  = "variable",
    values_to = "value"
  ) %>%
  group_by(country, wave, variable) %>%
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    # Respondent-level SD. With one country, every variable is min-max normalized
    # against its own series, which destroys magnitude — sd_value is what lets the
    # prospector rank variables by how far they moved rather than how steadily.
    sd_value   = sd(value, na.rm = TRUE),
    n          = sum(!is.na(value)),
    .groups    = "drop"
  ) %>%
  rename(wave_num = wave) %>%
  filter(!is.nan(mean_value), n > 0)

cat(sprintf("  Means table: %s rows (%d country x %d variables x %d waves)\n",
            format(nrow(means_long), big.mark = ","),
            n_distinct(means_long$country),
            n_distinct(means_long$variable),
            n_distinct(means_long$wave_num)))

# Save means for reproducibility
output_dir <- here("outputs", "prospecting", "kgss")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
means_csv <- file.path(output_dir, "kgss_means.csv")
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# ── 4. CONFIGURE AND RUN PROSPECTOR ──────────────────────────────────────────

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- output_dir
MIN_WAVES           <- 3        # drop vars with < 3 survey years
Z_THRESHOLD         <- 2.0      # outlier z-score threshold
# KGSS is one country, so a slope cannot be judged against other countries' slopes
# on the same variable — the reference distribution has one member and every z
# collapses to 0. "cross_variable" judges each variable against the same country's
# other variables ("of everything KGSS measures, this moved most"), which is the
# only reading available here. z values are therefore NOT comparable with a
# multi-country run's. See src/scripts/prospector/z_basis.R.
Z_BASIS             <- "cross_variable"
# ABS's FAST_THRESHOLD of 0.15 sits at the 99th percentile of the KGSS slope
# distribution, so magnitude: FAST would never fire. 0.09 is the KGSS value that
# matches ABS 0.15's selectivity (94th percentile in both).
FAST_THRESHOLD      <- 0.09
# A KGSS wave is a calendar YEAR; an ABS wave is 4 years (median interview year
# 2002/2007/2011/2015/2019/2022). So ABS's group flat band of 0.05 per wave is
# 0.0125 per year, and applying 0.05 to per-year KGSS group means put 22 of 24
# groups in the flat band — no signature could fire regardless of vocabulary.
# Variable-level FLAT_THRESHOLD stays at 0.05: those slopes are noise-dominated
# (min-max normalization fills each series' range), so the same conversion there
# would call ~86% of KGSS variables "moving".
GROUP_FLAT_THRESHOLD <- 0.0125
# Variable direction by magnitude rather than per-wave rate, for the same reason.
# The per-year slope of a KGSS series observed across 2003-2025 is capped at
# 1/22 = 0.045, below the 0.05 flat band, so long-running variables could never
# read RISING or FALLING however far they actually moved: pride_social_security
# runs 1.92 -> 2.89 on a 1-4 scale (1.39 respondent SDs) and read FLAT. 0.2 SD
# across the observed window is the bar now; the median KGSS variable moves 0.24.
DIRECTION_BASIS        <- "sd_units"
DIRECTION_SD_THRESHOLD <- 0.2
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups_kgss.yml")
# KGSS-vocabulary signatures. The default registry (signatures.yml) is written in
# ABS group names, of which KGSS shares three — pointing a KGSS run at it yields a
# permanently empty narrative_patterns.csv.
SIGNATURES_PATH     <- here("src", "scripts", "prospector", "signatures_kgss.yml")
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- FALSE    # meaningless with a single country
DO_NARRATIVE        <- TRUE     # check KGSS signatures in the KOR time series
DO_DASHBOARDS       <- TRUE     # main output: concept group trajectories over time
TITLE               <- "KGSS Korea (2003-2025)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
