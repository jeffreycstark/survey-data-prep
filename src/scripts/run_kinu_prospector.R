## ============================================================================
## run_kinu_prospector.R
## Run slope_prospector on KINU harmonized data (Korea, 2014-2023)
##
## Output: outputs/prospecting/kinu/
##
## NOTE: KINU is single-country (KOR). Country clustering is disabled.
## KINU has biannual fielding 2019-2021 (a/b sub-waves) — we exploit this
## by using a CONTINUOUS time axis (year + fieldwork_month/12) rather than
## integer year, giving the prospector finer temporal resolution than KGSS.
## ============================================================================

library(here)
library(tidyverse)

# ── 1. LOAD HARMONIZED KINU DATA ──────────────────────────────────────────────

cat("Loading KINU harmonized data...\n")
d <- readRDS(here("data", "processed", "kinu_harmonized.rds"))
cat(sprintf("  %s rows, %d vars, %d wave entries\n",
            format(nrow(d), big.mark = ","), ncol(d),
            n_distinct(d$wave)))

# ── 2. CONSTRUCT CONTINUOUS TIME AXIS ────────────────────────────────────────
#
# KINU year + (fieldwork_month - 6.5) / 12 gives each wave a position on a
# continuous decimal-year scale. April waves sit slightly below year-mark,
# September/October waves sit slightly above. For 2014-2017 (no month data),
# default to year (offset 0).

d <- d %>%
  mutate(
    fwm = ifelse(is.na(fieldwork_month), 6.5, fieldwork_month),
    wave_num = year + (fwm - 6.5) / 12
  )

cat("Time axis (decimal year):\n")
print(d %>% count(wave, year, fieldwork_month, wave_num) %>% arrange(wave_num))

# ── 3. SELECT VARIABLES FOR ANALYSIS ─────────────────────────────────────────

# Exclude system/identifier/weight variables
system_vars <- c("wave", "year", "fieldwork_month", "fwm", "country", "wave_num", "row_id")

# Exclude nominal/categorical variables (not ordinal scales)
nominal_vars <- c(
  "region",                    # 19-cat sido
  "home_region",               # 19-cat sido of origin
  "religion",                  # 5-cat affiliation
  "marital_status",            # 5-cat
  "employment",                # 12-cat
  "cohort",                    # 7-cat named generations (treat as categorical here)
  "nkpol_us_china_posture"     # 4-cat diplomatic-posture choice
)

# Exclude continuous identity vars not suitable for slope analysis
exclude_continuous <- c(
  "age",                       # individual age — not a temporal trend
  "birthyear",                 # individual birthyear — not a temporal trend
  "income_manwon"              # raw 만원 — too volatile across waves
)

exclude <- c(system_vars, nominal_vars, exclude_continuous)

numeric_vars <- names(d)[sapply(d, is.numeric)]
candidate_vars <- setdiff(numeric_vars, exclude)

# Drop vars with implausibly large values
var_maxabs <- sapply(candidate_vars, function(v) max(abs(d[[v]]), na.rm = TRUE))
vars <- candidate_vars[is.finite(var_maxabs) & var_maxabs <= 1000]

cat(sprintf("  Variables included in analysis: %d\n", length(vars)))

# ── 4. COMPUTE PER-WAVE MEANS ────────────────────────────────────────────────

cat("Computing per-wave means...\n")
means_long <- d %>%
  select(country, wave_num, all_of(vars)) %>%
  pivot_longer(
    cols      = all_of(vars),
    names_to  = "variable",
    values_to = "value"
  ) %>%
  group_by(country, wave_num, variable) %>%
  summarise(
    mean_value = mean(value, na.rm = TRUE),
    n          = sum(!is.na(value)),
    .groups    = "drop"
  ) %>%
  filter(!is.nan(mean_value), n > 0)

cat(sprintf("  Means table: %s rows (%d country x %d variables x %d waves)\n",
            format(nrow(means_long), big.mark = ","),
            n_distinct(means_long$country),
            n_distinct(means_long$variable),
            n_distinct(means_long$wave_num)))

# Save means for reproducibility
output_dir <- here("outputs", "prospecting", "kinu")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
means_csv <- file.path(output_dir, "kinu_means.csv")
write_csv(means_long, means_csv)
cat(sprintf("  Saved means to: %s\n", means_csv))

# ── 5. CONFIGURE AND RUN PROSPECTOR ──────────────────────────────────────────

INPUT_PATH          <- means_csv
OUTPUT_DIR          <- output_dir
MIN_WAVES           <- 3
Z_THRESHOLD         <- 2.0
CONCEPT_GROUPS_PATH <- here("src", "scripts", "concept_groups_kinu.yml")  # may not exist; gracefully skip
USE_WEIGHTED_SLOPES <- TRUE
DO_CLUSTERING       <- FALSE
DO_NARRATIVE        <- TRUE
DO_DASHBOARDS       <- TRUE
TITLE               <- "KINU Unification Survey (Korea, 2014-2023)"

cat(sprintf("\nRunning prospector -> %s\n\n", OUTPUT_DIR))
source(here("src", "scripts", "slope_prospector.R"))

cat("\nDone. Results in:", OUTPUT_DIR, "\n")
