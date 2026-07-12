## ============================================================================
## slope_prospector.R  (v2)
## Systematic detection of interesting trend patterns in harmonized survey data
##
## Purpose: Prospecting tool to identify countries/variables worth investigating.
## NOT a hypothesis-testing tool — findings here are puzzles, not conclusions.
##
## Input: Long-format harmonized data with columns:
##   - country:    country name
##   - wave_num:   numeric wave indicator (1, 2, 3, ...)
##   - variable:   variable name (e.g., "trust_military")
##   - mean_value: country-wave mean for that variable
##   - n:          (optional) respondent count; enables weighted slopes
##
## Output:
##   1. Ranked list of steepest slopes with CIs (outlier_slopes.csv)
##   2. Structural break detection (structural_breaks.csv)
##   3. Variable-level divergence (divergent_pairs.csv)
##   4. Acceleration / direction-reversal detection (acceleration.csv)
##   5. Concept group coherence with continuous coherence score (slope_groups.csv)
##   6. Cross-group divergence (slope_divergence.csv)
##   7. Country similarity clustering (country_clusters.csv)
##   8. Narrative pattern tags (narrative_patterns.csv)
##   9. Heatmap, outlier dotplot, country dashboards, cluster dendrogram
##  10. Summary report (prospecting_report.md)
## ============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(broom)
  library(strucchange)
  library(patchwork)
  library(yaml)
})

# ── 0. CONFIGURATION ──────────────────────────────────────────────────────────

# Required: point at your harmonized means CSV
if (!exists("INPUT_PATH"))   INPUT_PATH  <- "path/to/your/harmonized_means.csv"
if (!exists("OUTPUT_DIR"))   OUTPUT_DIR  <- "output/prospecting"

# Slope estimation
if (!exists("MIN_WAVES"))           MIN_WAVES           <- 3
if (!exists("Z_THRESHOLD"))         Z_THRESHOLD         <- 2.0
if (!exists("CI_ALPHA"))            CI_ALPHA            <- 0.05     # CI level for slopes
if (!exists("QUAD_MIN_WAVES"))      QUAD_MIN_WAVES      <- 4        # min waves to fit quadratic
if (!exists("FLAT_THRESHOLD"))      FLAT_THRESHOLD      <- 0.05     # |slope| below = "FLAT"
if (!exists("FAST_THRESHOLD"))      FAST_THRESHOLD      <- 0.15     # |mean_slope| above = "FAST"
if (!exists("ENDS_LOW"))            ENDS_LOW            <- 0.33     # normalized endpoint below = "LOW"
if (!exists("ENDS_HIGH"))           ENDS_HIGH           <- 0.66     # normalized endpoint above = "HIGH"
if (!exists("SHAPE_QUORUM"))        SHAPE_QUORUM        <- 0.5      # member share to assign a group shape

# Normalization: "minmax" (default) or "robust" (5th–95th percentile, outlier-resistant)
if (!exists("NORM_METHOD"))         NORM_METHOD         <- "minmax"

# Weighted slopes: if means CSV has a column `n`, use it for WLS; else equal weights
if (!exists("USE_WEIGHTED_SLOPES")) USE_WEIGHTED_SLOPES <- TRUE

# Variables / groups to exclude
if (!exists("VARS_OF_INTEREST"))    VARS_OF_INTEREST    <- NULL
if (!exists("EXCLUDE_VARS"))        EXCLUDE_VARS        <- c(
  "religion", "idnumber", "problem_most_important",
  "int_year", "int_month", "sample_elite_mass"
)
if (!exists("EXCLUDE_FROM_CROSS_GROUP")) EXCLUDE_FROM_CROSS_GROUP <- c(
  "political_action_contacting_protest",
  "political_action_voting"
)

# Concept groups YAML
if (!exists("CONCEPT_GROUPS_PATH")) CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"

# Optional: named list of additional means CSVs for cross-survey concordance
# e.g. SECONDARY_INPUT_PATHS <- list(WVS = "outputs/prospecting/wvs/wvs_means.csv")
if (!exists("SECONDARY_INPUT_PATHS")) SECONDARY_INPUT_PATHS <- NULL

# Feature flags
if (!exists("DO_CLUSTERING"))       DO_CLUSTERING       <- TRUE
if (!exists("DO_NARRATIVE"))        DO_NARRATIVE        <- TRUE
if (!exists("DO_DASHBOARDS"))       DO_DASHBOARDS       <- TRUE

# Plot title override (NULL = derived from INPUT_PATH)
if (!exists("TITLE"))               TITLE               <- NULL

# ── NARRATIVE PATTERN SIGNATURES ─────────────────────────────────────────────
# Signature definitions now live in src/scripts/prospector/signatures.yml,
# loaded and matched via the prospector/ module (see section 10 below).

source(here::here("src", "scripts", "prospector", "signature_features.R"))
source(here::here("src", "scripts", "prospector", "signature_match.R"))
SIGNATURES_PATH <- here::here("src", "scripts", "prospector", "signatures.yml")

# ── 1. LOAD AND PREPARE DATA ──────────────────────────────────────────────────

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

harmonized_data <- read_csv(INPUT_PATH, show_col_types = FALSE)

# Derive plot title from INPUT_PATH if not set
plot_title <- TITLE %||% tools::file_path_sans_ext(basename(INPUT_PATH))

# Drop excluded variables
if (length(EXCLUDE_VARS) > 0) {
  n_before <- n_distinct(harmonized_data$variable)
  harmonized_data <- harmonized_data %>% filter(!variable %in% EXCLUDE_VARS)
  n_dropped <- n_before - n_distinct(harmonized_data$variable)
  if (n_dropped > 0)
    cat(sprintf("Excluded %d variable(s) from EXCLUDE_VARS\n", n_dropped))
}

# Filter to variables of interest if specified
if (!is.null(VARS_OF_INTEREST))
  harmonized_data <- harmonized_data %>% filter(variable %in% VARS_OF_INTEREST)

has_n_col <- "n" %in% names(harmonized_data)
if (USE_WEIGHTED_SLOPES && has_n_col)
  cat("── Weighted slopes enabled (n column found) ──\n")

# ── 2. NORMALIZATION ──────────────────────────────────────────────────────────
# Normalize each variable to [0, 1] so slopes are scale-comparable.
# minmax:  uses observed min/max (default, simple)
# robust:  uses 5th–95th percentile (resists outlier country-waves)

if (NORM_METHOD == "robust") {
  harmonized_data <- harmonized_data %>%
    group_by(variable) %>%
    mutate(
      lo = quantile(mean_value, 0.05, na.rm = TRUE),
      hi = quantile(mean_value, 0.95, na.rm = TRUE),
      mean_value = if_else(
        hi > lo,
        pmin(pmax((mean_value - lo) / (hi - lo), 0), 1),
        0
      )
    ) %>%
    select(-lo, -hi) %>%
    ungroup()
  cat("── Variables normalized to [0, 1] using robust 5th–95th percentile ──\n")
} else {
  harmonized_data <- harmonized_data %>%
    group_by(variable) %>%
    mutate(
      lo = min(mean_value, na.rm = TRUE),
      hi = max(mean_value, na.rm = TRUE),
      mean_value = if_else(hi > lo, (mean_value - lo) / (hi - lo), 0)
    ) %>%
    select(-lo, -hi) %>%
    ungroup()
  cat("── Variables normalized to [0, 1] using observed min/max ──\n")
}

# Coverage summary
coverage <- harmonized_data %>%
  group_by(country, variable) %>%
  summarise(n_waves = n(), .groups = "drop")

cat("── Data coverage ──\n")
cat(sprintf("Countries: %d\n", n_distinct(harmonized_data$country)))
cat(sprintf("Variables: %d\n", n_distinct(harmonized_data$variable)))
cat(sprintf("Waves: %d\n",     n_distinct(harmonized_data$wave_num)))
cat(sprintf("Country-variable pairs with >= %d waves: %d\n",
            MIN_WAVES, sum(coverage$n_waves >= MIN_WAVES)))

# ── 3. SLOPE ESTIMATION ───────────────────────────────────────────────────────

# Helper: fit linear (and optionally quadratic) OLS for one group
.fit_lm <- function(df) {
  use_weights <- USE_WEIGHTED_SLOPES && "n" %in% names(df) && !all(is.na(df$n))
  w <- if (use_weights) df$n else NULL
  tryCatch(
    tidy(lm(mean_value ~ wave_num, data = df, weights = w)),
    error = function(e) tibble(term = character(), estimate = numeric(),
                               std.error = numeric(), p.value = numeric())
  )
}

.fit_quad <- function(df) {
  use_weights <- USE_WEIGHTED_SLOPES && "n" %in% names(df) && !all(is.na(df$n))
  w <- if (use_weights) df$n else NULL
  tryCatch({
    df2 <- df %>% mutate(wave_num2 = wave_num^2)
    tidy(lm(mean_value ~ wave_num + wave_num2, data = df2, weights = w))
  }, error = function(e) tibble())
}

# ── 3a. Linear slopes ─────────────────────────────────────────────────────────
cat("\n── Estimating linear slopes ──\n")

slopes_raw <- harmonized_data %>%
  group_by(country, variable) %>%
  filter(n() >= MIN_WAVES) %>%
  group_modify(~ .fit_lm(.x)) %>%
  ungroup()

slopes <- slopes_raw %>%
  filter(term == "wave_num") %>%
  select(country, variable, slope = estimate, se = std.error, p.value) %>%
  mutate(
    ci_lo = slope - qnorm(1 - CI_ALPHA / 2) * se,
    ci_hi = slope + qnorm(1 - CI_ALPHA / 2) * se,
    sig   = p.value < CI_ALPHA   # slope significantly different from zero
  )

# ── 3b. Quadratic / non-linearity flag ────────────────────────────────────────
cat("── Detecting non-linear trajectories (quadratic term) ──\n")

nonlinear_flags <- harmonized_data %>%
  group_by(country, variable) %>%
  filter(n() >= QUAD_MIN_WAVES) %>%
  group_modify(~ .fit_quad(.x)) %>%
  ungroup() %>%
  filter(term == "wave_num2") %>%
  select(country, variable,
         quad_term  = estimate,
         quad_se    = std.error,
         quad_pval  = p.value) %>%
  mutate(nonlinear = quad_pval < 0.10)

slopes <- slopes %>%
  left_join(nonlinear_flags, by = c("country", "variable")) %>%
  mutate(nonlinear = replace_na(nonlinear, FALSE))

# ── 3c. Z-score standardisation ───────────────────────────────────────────────
slopes <- slopes %>%
  group_by(variable) %>%
  mutate(
    n_countries = n(),
    mean_slope  = mean(slope, na.rm = TRUE),
    sd_slope    = sd(slope,   na.rm = TRUE),
    z_slope     = if_else(sd_slope > 0 & n_countries > 1,
                          (slope - mean_slope) / sd_slope, 0)
  ) %>%
  ungroup() %>%
  mutate(direction = case_when(
    slope >  FLAT_THRESHOLD ~ "RISING",
    slope < -FLAT_THRESHOLD ~ "FALLING",
    TRUE                    ~ "FLAT"
  ))

# ── 4. OUTLIER DETECTION ──────────────────────────────────────────────────────

outliers <- slopes %>%
  filter(abs(z_slope) > Z_THRESHOLD) %>%
  arrange(desc(abs(z_slope)))

cat(sprintf("\n── Outlier slopes (|z| > %.1f): %d found ──\n",
            Z_THRESHOLD, nrow(outliers)))
if (nrow(outliers) > 0) {
  outliers %>%
    select(country, variable, slope, z_slope, direction, sig, nonlinear) %>%
    mutate(across(where(is.numeric), ~ round(., 3))) %>%
    print(n = 30)
}

write_csv(outliers, file.path(OUTPUT_DIR, "outlier_slopes.csv"))

# ── 5. STRUCTURAL BREAK DETECTION ────────────────────────────────────────────

cat("\n── Running structural break tests ──\n")

eligible_for_breaks <- harmonized_data %>%
  group_by(country, variable) %>%
  filter(n() >= 4) %>%
  ungroup()

if (nrow(eligible_for_breaks) > 0) {
  break_results <- eligible_for_breaks %>%
    group_by(country, variable) %>%
    group_modify(~ {
      tryCatch({
        ts_data <- .x %>% arrange(wave_num)
        test <- suppressWarnings(
          sctest(mean_value ~ wave_num, data = ts_data, type = "supF")
        )
        tibble(n_waves = nrow(.x),
               statistic = test$statistic,
               p_value   = test$p.value)
      }, error = function(e) {
        tibble(n_waves = nrow(.x), statistic = NA_real_, p_value = NA_real_)
      })
    }) %>%
    ungroup() %>%
    filter(!is.na(p_value))
} else {
  cat("(Skipped — fewer than 4 waves in data)\n")
  break_results <- tibble(country = character(), variable = character(),
                          n_waves = integer(), statistic = numeric(), p_value = numeric())
}

significant_breaks <- break_results %>%
  filter(p_value < 0.05) %>%
  arrange(p_value)

cat(sprintf("Significant structural breaks (p < .05): %d found\n", nrow(significant_breaks)))
if (nrow(significant_breaks) > 0)
  significant_breaks %>% mutate(across(where(is.numeric), ~ round(., 3))) %>% print(n = 30)

write_csv(significant_breaks, file.path(OUTPUT_DIR, "structural_breaks.csv"))

# ── 6. DIVERGENCE DETECTION ──────────────────────────────────────────────────
# Pre-filter before self-join: only include variables with |slope| > FLAT_THRESHOLD
# This cuts the pair count by ~(filtered_n / total_n)^2, typically 60-80%.

slope_wide <- slopes %>% select(country, variable, slope)

slope_wide_filtered <- slope_wide %>%
  filter(abs(slope) > FLAT_THRESHOLD)

divergence <- slope_wide_filtered %>%
  rename(var1 = variable, slope1 = slope) %>%
  inner_join(
    slope_wide_filtered %>% rename(var2 = variable, slope2 = slope),
    by = "country", relationship = "many-to-many"
  ) %>%
  filter(var1 < var2) %>%
  mutate(
    divergence = abs(slope1 - slope2),
    direction1 = if_else(slope1 > 0, "+", "-"),
    direction2 = if_else(slope2 > 0, "+", "-"),
    opposite   = sign(slope1) != sign(slope2)
  )

opposite_movers <- divergence %>%
  filter(opposite) %>%
  arrange(desc(divergence))

cat(sprintf("\n── Opposite-direction variable pairs: %d found ──\n", nrow(opposite_movers)))
if (nrow(opposite_movers) > 0) {
  opposite_movers %>%
    select(country, var1, slope1, direction1, var2, slope2, direction2, divergence) %>%
    mutate(across(where(is.numeric), ~ round(., 3))) %>%
    print(n = 30)
}

write_csv(opposite_movers, file.path(OUTPUT_DIR, "divergent_pairs.csv"))

# ── 7. ACCELERATION DETECTION ────────────────────────────────────────────────

acceleration <- NULL   # reset so a stale prior value can't leak across repeated interactive source()

if (n_distinct(harmonized_data$wave_num) >= 4) {

  mid_wave <- median(unique(harmonized_data$wave_num))

  .slopes_period <- function(data, waves_filter) {
    data %>%
      filter({{ waves_filter }}) %>%
      group_by(country, variable) %>%
      filter(n() >= 2) %>%
      group_modify(~ .fit_lm(.x)) %>%
      ungroup() %>%
      filter(term == "wave_num") %>%
      select(country, variable, slope = estimate)
  }

  early_slopes <- .slopes_period(harmonized_data, wave_num <= mid_wave)
  late_slopes  <- .slopes_period(harmonized_data, wave_num >  mid_wave)

  acceleration <- early_slopes %>%
    rename(early_slope = slope) %>%
    inner_join(late_slopes %>% rename(late_slope = slope),
               by = c("country", "variable")) %>%
    mutate(
      acceleration     = late_slope - early_slope,
      direction_change = sign(early_slope) != sign(late_slope)
    ) %>%
    arrange(desc(abs(acceleration)))

  cat(sprintf("\n── Acceleration/deceleration patterns ──\n"))
  cat(sprintf("Direction reversals: %d\n", sum(acceleration$direction_change)))

  acceleration %>%
    filter(direction_change | abs(acceleration) > quantile(abs(acceleration), 0.9)) %>%
    mutate(across(where(is.numeric), ~ round(., 3))) %>%
    print(n = 30)

  write_csv(acceleration, file.path(OUTPUT_DIR, "acceleration.csv"))
}

# ── 8. CONCEPT GROUP ANALYSIS ────────────────────────────────────────────────

group_coherence <- tibble()
cross_group     <- tibble()

if (file.exists(CONCEPT_GROUPS_PATH)) {

  cat(sprintf("\n── Concept group analysis (%s) ──\n", CONCEPT_GROUPS_PATH))
  concept_groups_raw <- yaml.load_file(CONCEPT_GROUPS_PATH)

  group_lookup <- map_dfr(names(concept_groups_raw$concept_groups), function(grp) {
    tibble(group = grp, variable = concept_groups_raw$concept_groups[[grp]])
  })

  missing_from_data <- setdiff(group_lookup$variable, slopes$variable)
  if (length(missing_from_data) > 0) {
    cat(sprintf("Note: %d config variables not in data (check spelling or wave coverage):\n",
                length(missing_from_data)))
    cat(paste(" ", missing_from_data, collapse = "\n"), "\n")
  }

  slopes_grouped <- slopes %>%
    inner_join(group_lookup, by = "variable", relationship = "many-to-many")

  n_matched <- n_distinct(slopes_grouped$variable)
  n_total   <- n_distinct(slopes$variable)
  cat(sprintf("Variables matched to a group: %d / %d total in data\n", n_matched, n_total))
  cat(sprintf("Groups defined: %d\n", n_distinct(group_lookup$group)))

  # ── 8a. Group coherence ────────────────────────────────────────────────────
  # coherence_score: proportion of variables moving in the majority direction.
  # 1.0 = perfect agreement; 0.5 = half-and-half; interpretable and bounded.

  group_coherence <- slopes_grouped %>%
    group_by(country, group) %>%
    filter(n() >= 2) %>%
    summarise(
      n_vars          = n(),
      mean_slope      = mean(slope),
      sd_slope        = sd(slope),
      n_rising        = sum(slope >  FLAT_THRESHOLD),
      n_falling       = sum(slope < -FLAT_THRESHOLD),
      n_flat          = sum(abs(slope) <= FLAT_THRESHOLD),
      all_same_sign   = all(slope > 0) | all(slope < 0),
      coherence_score = max(n_rising, n_falling, n_flat) / n(),
      rising_vars     = paste(variable[slope >  FLAT_THRESHOLD], collapse = "; "),
      falling_vars    = paste(variable[slope < -FLAT_THRESHOLD], collapse = "; "),
      .groups         = "drop"
    ) %>%
    mutate(
      coherence_flag = case_when(
        all_same_sign & mean_slope >  FLAT_THRESHOLD ~ "COHERENT_RISING",
        all_same_sign & mean_slope < -FLAT_THRESHOLD ~ "COHERENT_FALLING",
        TRUE                                         ~ "DIVERGENT"
      ),
      group_direction = case_when(
        mean_slope >  FLAT_THRESHOLD ~ "RISING",
        mean_slope < -FLAT_THRESHOLD ~ "FALLING",
        TRUE                         ~ "FLAT"
      )
    ) %>%
    arrange(group, country)

  divergent_groups <- group_coherence %>%
    filter(coherence_flag == "DIVERGENT") %>%
    arrange(desc(sd_slope))

  cat(sprintf("\nGroup × country pairs assessed: %d\n", nrow(group_coherence)))
  cat(sprintf("Divergent groups (mixed direction within group): %d\n", nrow(divergent_groups)))

  if (nrow(divergent_groups) > 0) {
    cat("\nTop divergent groups — variables pulling in opposite directions:\n")
    divergent_groups %>%
      select(country, group, mean_slope, sd_slope, coherence_score,
             n_rising, n_falling, rising_vars, falling_vars) %>%
      mutate(across(where(is.numeric), ~ round(., 3))) %>%
      print(n = 20)
  }

  write_csv(group_coherence, file.path(OUTPUT_DIR, "slope_groups.csv"))
  cat(sprintf("── Saved: %s/slope_groups.csv ──\n", OUTPUT_DIR))

  # ── 8b. Cross-group divergence ─────────────────────────────────────────────

  global_slope_sd    <- sd(slopes$slope, na.rm = TRUE)
  cross_group_thresh <- 0.5 * global_slope_sd

  group_means <- group_coherence %>% select(country, group, mean_slope)
  group_means_cg <- group_means %>% filter(!group %in% EXCLUDE_FROM_CROSS_GROUP)

  excluded_cg <- intersect(EXCLUDE_FROM_CROSS_GROUP, unique(group_means$group))
  if (length(excluded_cg) > 0)
    cat(sprintf("Cross-group: excluding %d group(s): %s\n",
                length(excluded_cg), paste(excluded_cg, collapse = ", ")))

  cross_group <- group_means_cg %>%
    rename(group1 = group, slope1 = mean_slope) %>%
    inner_join(
      group_means_cg %>% rename(group2 = group, slope2 = mean_slope),
      by = "country", relationship = "many-to-many"
    ) %>%
    filter(group1 < group2) %>%
    mutate(
      slope_diff = abs(slope1 - slope2),
      direction1 = if_else(slope1 > 0, "RISING", "FALLING"),
      direction2 = if_else(slope2 > 0, "RISING", "FALLING"),
      opposite   = sign(slope1) != sign(slope2)
    ) %>%
    filter(slope_diff > cross_group_thresh) %>%
    arrange(desc(opposite), desc(slope_diff))

  cat(sprintf(
    "\n── Cross-group divergences (|Δslope| > %.3f = 0.5 SD): %d found ──\n",
    cross_group_thresh, nrow(cross_group)
  ))
  cat(sprintf("   Of which opposite direction: %d (highest priority)\n",
              sum(cross_group$opposite)))

  if (nrow(cross_group) > 0) {
    cross_group %>%
      select(country, group1, slope1, direction1,
             group2, slope2, direction2, slope_diff, opposite) %>%
      mutate(across(where(is.numeric), ~ round(., 3))) %>%
      print(n = 20)
  }

  write_csv(cross_group, file.path(OUTPUT_DIR, "slope_divergence.csv"))
  cat(sprintf("── Saved: %s/slope_divergence.csv ──\n", OUTPUT_DIR))

} else {
  cat(sprintf("\n── Concept group analysis skipped (no file at: %s) ──\n",
              CONCEPT_GROUPS_PATH))
}

# ── 9. COUNTRY CLUSTERING ────────────────────────────────────────────────────
# Cluster countries by their full slope vector. Reveals which countries
# share similar patterns of change across all variables.

if (DO_CLUSTERING && n_distinct(slopes$country) >= 3) {

  cat("\n── Country clustering ──\n")

  slope_mat <- slopes %>%
    select(country, variable, slope) %>%
    pivot_wider(names_from = variable, values_from = slope, values_fill = 0) %>%
    column_to_rownames("country") %>%
    as.matrix()

  dist_mat <- dist(slope_mat, method = "euclidean")
  hc       <- hclust(dist_mat, method = "ward.D2")

  k <- min(5, nrow(slope_mat) - 1)
  cluster_assignments <- cutree(hc, k = k)

  cluster_df <- tibble(
    country = names(cluster_assignments),
    cluster = cluster_assignments
  ) %>%
    arrange(cluster, country)

  cat(sprintf("Countries clustered into %d groups (ward.D2):\n", k))
  cluster_df %>%
    group_by(cluster) %>%
    summarise(countries = paste(country, collapse = ", "), .groups = "drop") %>%
    print()

  write_csv(cluster_df, file.path(OUTPUT_DIR, "country_clusters.csv"))

  # Dendrogram
  png(file.path(OUTPUT_DIR, "cluster_dendrogram.png"),
      width = max(800, n_distinct(slopes$country) * 60), height = 500, res = 120)
  par(mar = c(8, 4, 3, 2))
  plot(hc, main = sprintf("Country similarity: %s", plot_title),
       xlab = "", sub = "Ward.D2 linkage on slope vectors", cex = 0.85)
  rect.hclust(hc, k = k, border = "steelblue")
  dev.off()
  cat("── Cluster dendrogram saved ──\n")
}

# ── 10. NARRATIVE PATTERN TAGGING ────────────────────────────────────────────
narrative_results <- tibble()
if (DO_NARRATIVE && nrow(group_coherence) > 0) {
  cat("\n── Narrative pattern detection ──\n")
  sigs <- load_signatures(SIGNATURES_PATH)
  breaks_located <- augment_breaks_with_location(eligible_for_breaks, significant_breaks)
  thr <- list(FAST = FAST_THRESHOLD, ENDS_LOW = ENDS_LOW, ENDS_HIGH = ENDS_HIGH,
              SHAPE_QUORUM = SHAPE_QUORUM)
  acc_for_feat <- if (!is.null(acceleration)) acceleration else
                  tibble(country=character(), variable=character(),
                         early_slope=numeric(), late_slope=numeric(),
                         acceleration=numeric(), direction_change=logical())
  features <- build_group_features(group_coherence, harmonized_data, acc_for_feat,
                                   breaks_located, group_lookup, thr)
  var_slopes <- slopes %>% mutate(country = as.character(country)) %>%
                select(country, variable, direction)
  narrative_results <- match_signatures(features, sigs, var_slopes = var_slopes)
  cat(sprintf("%d narrative pattern matches found\n", nrow(narrative_results)))
  write_csv(narrative_results, file.path(OUTPUT_DIR, "narrative_patterns.csv"))
  cat(sprintf("── Saved: %s/narrative_patterns.csv ──\n", OUTPUT_DIR))
}

# ── 11. CROSS-SURVEY CONCORDANCE ─────────────────────────────────────────────
# If SECONDARY_INPUT_PATHS is a named list of additional means CSVs,
# compute slope correlations on shared variables.

if (!is.null(SECONDARY_INPUT_PATHS) && length(SECONDARY_INPUT_PATHS) > 0) {

  cat("\n── Cross-survey concordance ──\n")

  concordance_results <- map_dfr(names(SECONDARY_INPUT_PATHS), function(survey_name) {
    path2 <- SECONDARY_INPUT_PATHS[[survey_name]]
    if (!file.exists(path2)) {
      cat(sprintf("  Skipping %s: file not found at %s\n", survey_name, path2))
      return(tibble())
    }
    d2 <- read_csv(path2, show_col_types = FALSE)
    slopes2 <- d2 %>%
      group_by(country, variable) %>%
      filter(n() >= MIN_WAVES) %>%
      group_modify(~ .fit_lm(.x)) %>%
      ungroup() %>%
      filter(term == "wave_num") %>%
      select(country, variable, slope2 = estimate)

    shared_vars <- intersect(slopes$variable, slopes2$variable)
    if (length(shared_vars) == 0) {
      cat(sprintf("  %s: no shared variables with primary input\n", survey_name))
      return(tibble())
    }

    combined <- slopes %>%
      filter(variable %in% shared_vars) %>%
      select(country, variable, slope1 = slope) %>%
      inner_join(slopes2 %>% filter(variable %in% shared_vars),
                 by = c("country", "variable"))

    r <- cor(combined$slope1, combined$slope2, use = "complete.obs")
    cat(sprintf("  %s: %d shared variables, slope correlation r = %.3f\n",
                survey_name, length(shared_vars), r))

    combined %>%
      mutate(survey = survey_name, cor_overall = r)
  })

  if (nrow(concordance_results) > 0)
    write_csv(concordance_results, file.path(OUTPUT_DIR, "cross_survey_concordance.csv"))
}

# ── 12. VISUALIZATIONS ───────────────────────────────────────────────────────

# ── 12a. Slope heatmap ───────────────────────────────────────────────────────
p_heatmap <- slopes %>%
  ggplot(aes(x = variable, y = reorder(country, z_slope), fill = z_slope)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_gradient2(
    low = "#d73027", mid = "white", high = "#4575b4",
    midpoint = 0, name = "Z-score\n(slope)"
  ) +
  theme_minimal(base_size = 11) +
  theme(axis.text.x  = element_text(angle = 45, hjust = 1),
        panel.grid   = element_blank()) +
  labs(
    title    = sprintf("Slope heatmap: %s", plot_title),
    subtitle = sprintf("Red = decline  Blue = increase  |z| > %.1f = outlier", Z_THRESHOLD),
    x = NULL, y = NULL
  )

ggsave(file.path(OUTPUT_DIR, "heatmap_slopes.png"), p_heatmap,
       width = 10, height = max(6, n_distinct(slopes$country) * 0.4), dpi = 150)

# ── 12b. Outlier dotplot ─────────────────────────────────────────────────────
if (nrow(outliers) > 0) {
  p_outliers <- outliers %>%
    mutate(label = paste(country, variable, sep = " | "),
           shape = if_else(nonlinear, "Non-linear", "Linear")) %>%
    ggplot(aes(x = z_slope, y = reorder(label, z_slope))) +
    geom_errorbarh(aes(xmin = (ci_lo - mean_slope) / sd_slope,
                       xmax = (ci_hi - mean_slope) / sd_slope),
                   height = 0.3, alpha = 0.4) +
    geom_point(aes(color = direction, shape = shape), size = 3) +
    geom_vline(xintercept = 0, linetype = "dashed", alpha = 0.5) +
    scale_color_manual(values = c("FALLING" = "#d73027",
                                  "RISING"  = "#4575b4",
                                  "FLAT"    = "grey60")) +
    scale_shape_manual(values = c("Linear" = 16, "Non-linear" = 17)) +
    theme_minimal(base_size = 11) +
    labs(title    = "Outlier slopes",
         subtitle = sprintf("|z| > %.1f  (triangles = non-linear trajectory)", Z_THRESHOLD),
         x = "Standardized slope (z-score)", y = NULL,
         color = NULL, shape = NULL)

  ggsave(file.path(OUTPUT_DIR, "outlier_dotplot.png"), p_outliers,
         width = 8, height = max(4, nrow(outliers) * 0.35), dpi = 150)
}

# ── 12c. Country dashboards (concept group trajectories) ─────────────────────
# One faceted dashboard per country showing all concept group mean trends.

if (DO_DASHBOARDS && nrow(group_coherence) > 0) {

  dashboard_data <- harmonized_data %>%
    inner_join(
      map_dfr(names(concept_groups_raw$concept_groups), function(grp) {
        tibble(group = grp, variable = concept_groups_raw$concept_groups[[grp]])
      }),
      by = "variable", relationship = "many-to-many"
    ) %>%
    group_by(country, group, wave_num) %>%
    summarise(group_mean = mean(mean_value, na.rm = TRUE), .groups = "drop") %>%
    left_join(group_coherence %>% select(country, group, coherence_flag),
              by = c("country", "group"))

  flag_colours <- c(COHERENT_RISING  = "#4575b4",
                    COHERENT_FALLING = "#d73027",
                    DIVERGENT        = "#f4a582")

  walk(unique(dashboard_data$country), function(cty) {
    p_dash <- dashboard_data %>%
      filter(country == cty) %>%
      ggplot(aes(x = wave_num, y = group_mean, color = coherence_flag)) +
      geom_line(linewidth = 1) +
      geom_point(size = 2) +
      scale_y_continuous(limits = c(0, 1), labels = scales::percent) +
      scale_color_manual(values = flag_colours, na.value = "grey70",
                         name = "Coherence") +
      facet_wrap(~ group, ncol = 4) +
      theme_minimal(base_size = 9) +
      theme(legend.position = "bottom",
            strip.text       = element_text(size = 7, face = "bold")) +
      labs(title    = sprintf("Concept group trajectories: %s", cty),
           subtitle = "Normalized [0–1]  |  Blue=rising  Red=falling  Orange=divergent",
           x = "Wave", y = NULL)

    fname <- sprintf("dashboard_%s.png",
                     str_to_lower(str_replace_all(cty, "\\s+", "_")))
    ggsave(file.path(OUTPUT_DIR, fname), p_dash,
           width = 14, height = max(6, ceiling(n_distinct(dashboard_data$group) / 4) * 2.5),
           dpi = 150)
  })

  cat(sprintf("── Country dashboards saved (%d countries) ──\n",
              n_distinct(dashboard_data$country)))
}

# ── 12d. Country profile function (deep-dive) ────────────────────────────────
plot_country_profile <- function(data, target_country) {
  country_data <- data %>% filter(country == target_country)
  if (nrow(country_data) == 0) {
    warning(sprintf("No data found for %s", target_country))
    return(NULL)
  }
  p <- country_data %>%
    ggplot(aes(x = wave_num, y = mean_value, color = variable)) +
    geom_line(linewidth = 0.8) +
    geom_point(size = 2) +
    theme_minimal(base_size = 11) +
    labs(title = sprintf("Trend profile: %s", target_country),
         x = "Wave", y = "Normalized mean (0–1)", color = NULL) +
    theme(legend.position = "bottom")
  fname <- sprintf("profile_%s.png",
                   str_to_lower(str_replace_all(target_country, "\\s+", "_")))
  ggsave(file.path(OUTPUT_DIR, fname), p, width = 8, height = 5, dpi = 150)
  p
}

# Auto-generate profiles for outlier countries
if (nrow(outliers) > 0) {
  outlier_countries <- unique(outliers$country)
  cat(sprintf("\n── Generating profiles for %d outlier countries ──\n",
              length(outlier_countries)))
  walk(outlier_countries, ~ plot_country_profile(harmonized_data, .x))
}

cat("\n── Heatmap saved ──\n")

# ── 13. SUMMARY REPORT ───────────────────────────────────────────────────────

nonlinear_count <- sum(slopes$nonlinear, na.rm = TRUE)

narrative_section <- if (nrow(narrative_results) > 0) {
  narrative_results %>%
    arrange(country, label) %>%
    mutate(line = sprintf("- **%s** → %s: %s", country, label, description)) %>%
    pull(line)
} else {
  "- No matches found"
}

cluster_section <- if (nrow(group_coherence) > 0 && DO_CLUSTERING &&
                       exists("cluster_df") && nrow(cluster_df) > 0) {
  cluster_df %>%
    group_by(cluster) %>%
    summarise(countries = paste(country, collapse = ", "), .groups = "drop") %>%
    mutate(line = sprintf("- Cluster %d: %s", cluster, countries)) %>%
    pull(line)
} else {
  "- Clustering not run or insufficient countries"
}

summary_lines <- c(
  "# Slope Prospector v2: Summary Report",
  sprintf("Date: %s", Sys.Date()),
  sprintf("Input: %s", INPUT_PATH),
  sprintf("Normalization: %s", NORM_METHOD),
  "",
  "## Coverage",
  sprintf("- Countries: %d", n_distinct(harmonized_data$country)),
  sprintf("- Variables: %d", n_distinct(harmonized_data$variable)),
  sprintf("- Waves: %d", n_distinct(harmonized_data$wave_num)),
  "",
  "## Findings — Individual Variables",
  sprintf("- Outlier slopes (|z| > %.1f): %d", Z_THRESHOLD, nrow(outliers)),
  sprintf("- Of which non-linear trajectory: %d", sum(outliers$nonlinear, na.rm = TRUE)),
  sprintf("- Structural breaks (p < .05): %d", nrow(significant_breaks)),
  sprintf("- Opposite-direction variable pairs: %d", nrow(opposite_movers)),
  sprintf("- Variables with non-linear trajectory (all): %d", nonlinear_count),
  "",
  "## Top Outliers (by |z-score|)",
  if (nrow(outliers) > 0) {
    outliers %>%
      head(10) %>%
      mutate(line = sprintf("- %s | %s: slope=%.3f z=%.2f %s%s",
                            country, variable, slope, z_slope, direction,
                            if_else(nonlinear, " [NON-LINEAR]", ""))) %>%
      pull(line)
  } else "- None found",
  "",
  "## Findings — Concept Groups",
  if (nrow(group_coherence) > 0) {
    c(
      sprintf("- Groups defined: %d", n_distinct(group_coherence$group)),
      sprintf("- Group × country pairs assessed: %d", nrow(group_coherence)),
      sprintf("- Divergent groups (mixed direction): %d",
              sum(group_coherence$coherence_flag == "DIVERGENT")),
      sprintf("- Cross-group divergences flagged: %d", nrow(cross_group)),
      sprintf("- Cross-group, opposite direction: %d",
              if (nrow(cross_group) > 0) sum(cross_group$opposite) else 0)
    )
  } else "- Concept group analysis not run",
  "",
  "## Top Divergent Concept Groups",
  if (nrow(group_coherence) > 0 && any(group_coherence$coherence_flag == "DIVERGENT")) {
    group_coherence %>%
      filter(coherence_flag == "DIVERGENT") %>%
      arrange(desc(sd_slope)) %>%
      head(10) %>%
      mutate(line = sprintf(
        "- %s | %s: mean slope=%.3f coherence=%.2f rising=[%s] falling=[%s]",
        country, group, mean_slope, coherence_score, rising_vars, falling_vars
      )) %>%
      pull(line)
  } else "- None found",
  "",
  "## Top Cross-Group Divergences (opposite direction)",
  if (nrow(cross_group) > 0 && any(cross_group$opposite)) {
    cross_group %>%
      filter(opposite) %>%
      head(10) %>%
      mutate(line = sprintf(
        "- %s: [%s] %s (%.3f) vs [%s] %s (%.3f) | Δ=%.3f",
        country, group1, direction1, slope1, group2, direction2, slope2, slope_diff
      )) %>%
      pull(line)
  } else "- None found",
  "",
  "## Narrative Patterns Detected",
  narrative_section,
  "",
  "## Country Clusters",
  cluster_section,
  "",
  "## Files",
  sprintf("- %s/outlier_slopes.csv        (slopes + CIs + nonlinear flag)", OUTPUT_DIR),
  sprintf("- %s/structural_breaks.csv", OUTPUT_DIR),
  sprintf("- %s/divergent_pairs.csv", OUTPUT_DIR),
  sprintf("- %s/acceleration.csv", OUTPUT_DIR),
  sprintf("- %s/slope_groups.csv          (+ coherence_score column)", OUTPUT_DIR),
  sprintf("- %s/slope_divergence.csv", OUTPUT_DIR),
  sprintf("- %s/country_clusters.csv", OUTPUT_DIR),
  sprintf("- %s/narrative_patterns.csv", OUTPUT_DIR),
  sprintf("- %s/heatmap_slopes.png", OUTPUT_DIR),
  sprintf("- %s/cluster_dendrogram.png", OUTPUT_DIR),
  sprintf("- %s/dashboard_*.png           (one per country)", OUTPUT_DIR),
  "",
  "## REMINDER",
  "These are PUZZLES, not findings. Each outlier or divergent group needs:",
  "1. A check of the political timeline — is there a real-world explanation?",
  "2. A check of survey methodology — did sampling or questions change?",
  "3. A theoretical framework — why would this pattern exist?",
  "Only then does it become a paper."
)

writeLines(summary_lines, file.path(OUTPUT_DIR, "prospecting_report.md"))
cat("\n── Summary report saved ──\n")
cat("── Done. Happy prospecting! ──\n")
