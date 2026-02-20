## ============================================================================
## slope_prospector.R
## Systematic detection of interesting trend patterns in harmonized survey data
## 
## Purpose: Prospecting tool to identify countries/variables worth investigating.
## NOT a hypothesis-testing tool — findings here are puzzles, not conclusions.
##
## Input: Long-format harmonized data with columns:
##   - country: country name
##   - wave_num: numeric wave indicator (1, 2, 3, ...)
##   - variable: variable name (e.g., "trust_military", "trust_govt")
##   - mean_value: country-wave mean for that variable
##
## Output: 
##   1. Ranked list of steepest slopes (outlier detection)
##   2. Structural break detection (stable-then-broke patterns)
##   3. Divergence detection (variables moving in opposite directions)
##   4. Heatmap visualization for quick scanning
##   5. Country profile plots for deep dives
## ============================================================================

library(tidyverse)
library(broom)
library(strucchange)
library(patchwork)
library(yaml)

# ── 0. CONFIGURATION ──────────────────────────────────────────────────────────

# Point this at your harmonized data
# Expected format: long, with columns country, wave_num, variable, mean_value
# Can be pre-set before sourcing: INPUT_PATH <- "..."
if (!exists("INPUT_PATH")) INPUT_PATH <- "path/to/your/harmonized_means.csv"
if (!exists("OUTPUT_DIR")) OUTPUT_DIR  <- "output/prospecting"

# Minimum number of waves required to estimate a slope
if (!exists("MIN_WAVES"))           MIN_WAVES           <- 3
if (!exists("Z_THRESHOLD"))         Z_THRESHOLD         <- 2.0
if (!exists("VARS_OF_INTEREST"))    VARS_OF_INTEREST    <- NULL

# Variables to drop before any analysis (nominal vars, admin IDs, etc.)
# These inflate the global slope SD and break z-score and cross-group thresholds.
# Example: EXCLUDE_VARS <- c("religion", "idnumber", "problem_most_important")
if (!exists("EXCLUDE_VARS"))        EXCLUDE_VARS        <- c(
  "religion", "idnumber", "problem_most_important",
  "int_year", "int_month"
)

# Path to concept group definitions YAML
# Default: concept_groups.yml in the same directory as this script
if (!exists("CONCEPT_GROUPS_PATH")) CONCEPT_GROUPS_PATH <- "src/scripts/concept_groups.yml"

# ── 1. LOAD AND PREPARE DATA ─────────────────────────────────────────────────

dir.create(OUTPUT_DIR, recursive = TRUE, showWarnings = FALSE)

harmonized_data <- read_csv(INPUT_PATH, show_col_types = FALSE)

# Drop excluded variables (nominal IDs, open-ended categories, admin fields)
if (length(EXCLUDE_VARS) > 0) {
  n_before <- n_distinct(harmonized_data$variable)
  harmonized_data <- harmonized_data %>%
    filter(!variable %in% EXCLUDE_VARS)
  n_dropped <- n_before - n_distinct(harmonized_data$variable)
  if (n_dropped > 0)
    cat(sprintf("Excluded %d variable(s): %s\n", n_dropped,
                paste(intersect(EXCLUDE_VARS, unique(harmonized_data$variable)), collapse = ", ")))
}

# Filter to variables of interest if specified
if (!is.null(VARS_OF_INTEREST)) {
  harmonized_data <- harmonized_data %>%
    filter(variable %in% VARS_OF_INTEREST)
}

# Quick summary of coverage
coverage <- harmonized_data %>%
  group_by(country, variable) %>%
  summarise(n_waves = n(), .groups = "drop")

cat("── Data coverage ──\n")
cat(sprintf("Countries: %d\n", n_distinct(harmonized_data$country)))
cat(sprintf("Variables: %d\n", n_distinct(harmonized_data$variable)))
cat(sprintf("Waves: %d\n", n_distinct(harmonized_data$wave_num)))
cat(sprintf("Country-variable pairs with >= %d waves: %d\n",
            MIN_WAVES, sum(coverage$n_waves >= MIN_WAVES)))

# ── 2. LINEAR SLOPE ESTIMATION ───────────────────────────────────────────────
# Fit OLS slope per country-variable pair
# This gives the average rate of change per wave

slopes <- harmonized_data %>%
  group_by(country, variable) %>%
  filter(n() >= MIN_WAVES) %>%
  do(tidy(lm(mean_value ~ wave_num, data = .))) %>%
  filter(term == "wave_num") %>%
  ungroup() %>%
  select(country, variable, slope = estimate, se = std.error, p.value)

# Standardize slopes within each variable
# (allows cross-variable comparison despite different scales)
slopes <- slopes %>%
  group_by(variable) %>%
  mutate(
    mean_slope = mean(slope),
    sd_slope = sd(slope),
    z_slope = if_else(sd_slope > 0, (slope - mean_slope) / sd_slope, 0)
  ) %>%
  ungroup()

# ── 3. OUTLIER DETECTION ─────────────────────────────────────────────────────
# Flag country-variable pairs with unusually steep slopes

outliers <- slopes %>%
  filter(abs(z_slope) > Z_THRESHOLD) %>%
  arrange(desc(abs(z_slope))) %>%
  mutate(direction = if_else(slope > 0, "RISING", "FALLING"))

cat(sprintf("\n── Outlier slopes (|z| > %.1f): %d found ──\n",
            Z_THRESHOLD, nrow(outliers)))
if (nrow(outliers) > 0) {
  outliers %>%
    select(country, variable, slope, z_slope, direction) %>%
    mutate(across(where(is.numeric), ~ round(., 3))) %>%
    print(n = 30)
}

write_csv(outliers, file.path(OUTPUT_DIR, "outlier_slopes.csv"))

# ── 4. STRUCTURAL BREAK DETECTION ────────────────────────────────────────────
# Tests whether there's a point where the trend changes significantly
# This catches the "stable then broke" pattern (like Thailand W5-W6)

cat("\n── Running structural break tests ──\n")

eligible_for_breaks <- harmonized_data %>%
  group_by(country, variable) %>%
  filter(n() >= 4) %>%
  ungroup()

if (nrow(eligible_for_breaks) > 0) {
  break_results <- eligible_for_breaks %>%
    group_by(country, variable) %>%
    summarise(
      n_waves = n(),
      break_test = list(
        tryCatch({
          ts_data <- pick(everything()) %>% arrange(wave_num)
          test <- sctest(mean_value ~ wave_num, data = ts_data, type = "supF")
          tibble(statistic = test$statistic, p_value = test$p.value)
        }, error = function(e) {
          tibble(statistic = NA_real_, p_value = NA_real_)
        })
      ),
      .groups = "drop"
    ) %>%
    unnest(break_test) %>%
    filter(!is.na(p_value))
} else {
  cat("(Skipped — fewer than 4 waves in data)\n")
  break_results <- tibble(country = character(), variable = character(),
                          n_waves = integer(), statistic = numeric(),
                          p_value = numeric())
}

# Flag significant breaks
significant_breaks <- break_results %>%
  filter(p_value < 0.05) %>%
  arrange(p_value)

cat(sprintf("Significant structural breaks (p < .05): %d found\n",
            nrow(significant_breaks)))
if (nrow(significant_breaks) > 0) {
  significant_breaks %>%
    mutate(across(where(is.numeric), ~ round(., 3))) %>%
    print(n = 30)
}

write_csv(significant_breaks, file.path(OUTPUT_DIR, "structural_breaks.csv"))

# ── 5. DIVERGENCE DETECTION ──────────────────────────────────────────────────
# Find country-variable PAIRS where two variables move in opposite directions
# These are your sensitivity-gradient-style puzzles

slope_wide <- slopes %>%
  select(country, variable, slope)

divergence <- slope_wide %>%
  rename(var1 = variable, slope1 = slope) %>%
  inner_join(
    slope_wide %>% rename(var2 = variable, slope2 = slope),
    by = "country"
  ) %>%
  filter(var1 < var2) %>%  # avoid duplicate pairs
  mutate(
    divergence = abs(slope1 - slope2),
    direction1 = if_else(slope1 > 0, "+", "-"),
    direction2 = if_else(slope2 > 0, "+", "-"),
    opposite = sign(slope1) != sign(slope2)
  )

# Focus on opposite-direction pairs, ranked by magnitude
opposite_movers <- divergence %>%
  filter(opposite) %>%
  arrange(desc(divergence))

cat(sprintf("\n── Opposite-direction variable pairs: %d found ──\n",
            nrow(opposite_movers)))
if (nrow(opposite_movers) > 0) {
  opposite_movers %>%
    select(country, var1, slope1, direction1, var2, slope2, direction2, divergence) %>%
    mutate(across(where(is.numeric), ~ round(., 3))) %>%
    print(n = 30)
}

write_csv(opposite_movers, file.path(OUTPUT_DIR, "divergent_pairs.csv"))

# ── 6. ACCELERATION DETECTION ────────────────────────────────────────────────
# Compare early-period vs late-period slopes
# Catches cases where decline/increase is accelerating

if (n_distinct(harmonized_data$wave_num) >= 4) {
  
  mid_wave <- median(unique(harmonized_data$wave_num))
  
  early_slopes <- harmonized_data %>%
    filter(wave_num <= mid_wave) %>%
    group_by(country, variable) %>%
    filter(n() >= 2) %>%
    do(tidy(lm(mean_value ~ wave_num, data = .))) %>%
    filter(term == "wave_num") %>%
    ungroup() %>%
    select(country, variable, early_slope = estimate)
  
  late_slopes <- harmonized_data %>%
    filter(wave_num > mid_wave) %>%
    group_by(country, variable) %>%
    filter(n() >= 2) %>%
    do(tidy(lm(mean_value ~ wave_num, data = .))) %>%
    filter(term == "wave_num") %>%
    ungroup() %>%
    select(country, variable, late_slope = estimate)
  
  acceleration <- early_slopes %>%
    inner_join(late_slopes, by = c("country", "variable")) %>%
    mutate(
      acceleration = late_slope - early_slope,
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

# ── 7. CONCEPT GROUP ANALYSIS ────────────────────────────────────────────────
# Detects whether theoretically related variables move coherently (all same
# direction) or divergently (mixed directions — the interesting stories).
# Requires concept_groups.yml at CONCEPT_GROUPS_PATH.

if (file.exists(CONCEPT_GROUPS_PATH)) {

  cat(sprintf("\n── Concept group analysis (%s) ──\n", CONCEPT_GROUPS_PATH))
  concept_groups_raw <- yaml.load_file(CONCEPT_GROUPS_PATH)

  # Build variable → group lookup table
  group_lookup <- map_dfr(names(concept_groups_raw$concept_groups), function(grp) {
    tibble(group = grp, variable = concept_groups_raw$concept_groups[[grp]])
  })

  # Warn about variables named in config but absent from data
  missing_from_data <- setdiff(group_lookup$variable, slopes$variable)
  if (length(missing_from_data) > 0) {
    cat(sprintf("Note: %d config variables not in data (check spelling or wave coverage):\n",
                length(missing_from_data)))
    cat(paste(" ", missing_from_data, collapse = "\n"), "\n")
  }

  # Join slopes with group assignments (inner — only matched vars contribute)
  slopes_grouped <- slopes %>%
    inner_join(group_lookup, by = "variable")

  n_matched <- n_distinct(slopes_grouped$variable)
  n_total   <- n_distinct(slopes$variable)
  cat(sprintf("Variables matched to a group: %d / %d total in data\n", n_matched, n_total))
  cat(sprintf("Groups defined: %d\n", n_distinct(group_lookup$group)))

  # ── 7a. Group coherence report ─────────────────────────────────────────────
  # For each country × group: mean slope, direction coherence, divergent vars.
  # Coherence flags:
  #   COHERENT_RISING  — all variables in the group are rising
  #   COHERENT_FALLING — all variables in the group are falling
  #   DIVERGENT        — mixed directions (theoretically most interesting)

  group_coherence <- slopes_grouped %>%
    group_by(country, group) %>%
    filter(n() >= 2) %>%   # need at least 2 variables to assess coherence
    summarise(
      n_vars        = n(),
      mean_slope    = mean(slope),
      sd_slope      = sd(slope),
      n_rising      = sum(slope > 0),
      n_falling     = sum(slope < 0),
      all_same_sign = all(slope > 0) | all(slope < 0),
      rising_vars   = paste(variable[slope > 0],  collapse = "; "),
      falling_vars  = paste(variable[slope <= 0], collapse = "; "),
      .groups       = "drop"
    ) %>%
    mutate(
      coherence_flag = case_when(
        all_same_sign & mean_slope >  0 ~ "COHERENT_RISING",
        all_same_sign & mean_slope <= 0 ~ "COHERENT_FALLING",
        TRUE                            ~ "DIVERGENT"
      )
    ) %>%
    arrange(group, country)

  divergent_groups <- group_coherence %>%
    filter(coherence_flag == "DIVERGENT") %>%
    arrange(desc(sd_slope))

  cat(sprintf("\nGroup × country pairs assessed: %d\n", nrow(group_coherence)))
  cat(sprintf("Divergent groups (mixed direction within group): %d\n",
              nrow(divergent_groups)))

  if (nrow(divergent_groups) > 0) {
    cat("\nTop divergent groups — variables pulling in opposite directions:\n")
    divergent_groups %>%
      select(country, group, mean_slope, sd_slope, n_rising, n_falling,
             rising_vars, falling_vars) %>%
      mutate(across(where(is.numeric), ~ round(., 3))) %>%
      print(n = 20)
  }

  write_csv(group_coherence, file.path(OUTPUT_DIR, "slope_groups.csv"))
  cat(sprintf("── Saved: %s/slope_groups.csv ──\n", OUTPUT_DIR))

  # ── 7b. Cross-group divergence ─────────────────────────────────────────────
  # For each country, compare every pair of concept groups.
  # Flag pairs where the difference in group mean slopes exceeds
  # 0.5 SD of the overall (individual-variable) slope distribution.
  # Opposite-direction pairs are sorted first — those are your paper hypotheses.

  global_slope_sd    <- sd(slopes$slope, na.rm = TRUE)
  cross_group_thresh <- 0.5 * global_slope_sd

  group_means <- group_coherence %>%
    select(country, group, mean_slope)

  cross_group <- group_means %>%
    rename(group1 = group, slope1 = mean_slope) %>%
    inner_join(
      group_means %>% rename(group2 = group, slope2 = mean_slope),
      by = "country"
    ) %>%
    filter(group1 < group2) %>%   # unique pairs only
    mutate(
      slope_diff = abs(slope1 - slope2),
      direction1 = if_else(slope1 > 0, "RISING",  "FALLING"),
      direction2 = if_else(slope2 > 0, "RISING",  "FALLING"),
      opposite   = sign(slope1) != sign(slope2)
    ) %>%
    filter(slope_diff > cross_group_thresh) %>%
    # Opposite-direction pairs first, then by magnitude
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
  cat(sprintf(
    "\n── Concept group analysis skipped (no file at: %s) ──\n",
    CONCEPT_GROUPS_PATH
  ))
  group_coherence <- tibble()
  cross_group     <- tibble()
}

# ── 8. VISUALIZATIONS ────────────────────────────────────────────────────────

# 7a. Heatmap: all slopes at a glance
p_heatmap <- slopes %>%
  ggplot(aes(x = variable, y = reorder(country, z_slope), fill = z_slope)) +
  geom_tile(color = "white", linewidth = 0.3) +
  scale_fill_gradient2(
    low = "#d73027", mid = "white", high = "#4575b4",
    midpoint = 0, name = "Z-score\n(slope)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    axis.text.x = element_text(angle = 45, hjust = 1),
    panel.grid = element_blank()
  ) +
  labs(
    title = "Institutional trust slopes by country and variable",
    subtitle = sprintf("Red = steep decline, Blue = steep increase | Outlier threshold: |z| > %.1f", Z_THRESHOLD),
    x = NULL, y = NULL
  )

ggsave(file.path(OUTPUT_DIR, "heatmap_slopes.png"), p_heatmap,
       width = 10, height = max(6, n_distinct(slopes$country) * 0.4), dpi = 150)

cat("\n── Heatmap saved ──\n")

# 7b. Slope ranking dot plot (top outliers)
if (nrow(outliers) > 0) {
  p_outliers <- outliers %>%
    mutate(label = paste(country, variable, sep = " | ")) %>%
    ggplot(aes(x = z_slope, y = reorder(label, z_slope))) +
    geom_point(aes(color = direction), size = 3) +
    geom_vline(xintercept = 0, linetype = "dashed", alpha = 0.5) +
    scale_color_manual(values = c("FALLING" = "#d73027", "RISING" = "#4575b4")) +
    theme_minimal(base_size = 11) +
    labs(
      title = "Outlier slopes",
      subtitle = sprintf("|z| > %.1f", Z_THRESHOLD),
      x = "Standardized slope (z-score)", y = NULL, color = NULL
    )
  
  ggsave(file.path(OUTPUT_DIR, "outlier_dotplot.png"), p_outliers,
         width = 8, height = max(4, nrow(outliers) * 0.35), dpi = 150)
}

# 7c. Country deep-dive function
# Use this to plot all variables for a specific country after identifying it
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
    labs(
      title = sprintf("Trend profile: %s", target_country),
      x = "Wave", y = "Mean value", color = NULL
    ) +
    theme(legend.position = "bottom")
  
  ggsave(file.path(OUTPUT_DIR, sprintf("profile_%s.png",
                                        str_to_lower(str_replace_all(target_country, " ", "_")))),
         p, width = 8, height = 5, dpi = 150)
  
  return(p)
}

# Example: generate profiles for all outlier countries
if (nrow(outliers) > 0) {
  outlier_countries <- unique(outliers$country)
  cat(sprintf("\n── Generating profiles for %d outlier countries ──\n",
              length(outlier_countries)))
  walk(outlier_countries, ~ plot_country_profile(harmonized_data, .x))
}

# ── 9. SUMMARY REPORT ────────────────────────────────────────────────────────

summary_lines <- c(
  "# Slope Prospector: Summary Report",
  sprintf("Date: %s", Sys.Date()),
  sprintf("Input: %s", INPUT_PATH),
  "",
  "## Coverage",
  sprintf("- Countries: %d", n_distinct(harmonized_data$country)),
  sprintf("- Variables: %d", n_distinct(harmonized_data$variable)),
  sprintf("- Waves: %d", n_distinct(harmonized_data$wave_num)),
  "",
  "## Findings — Individual Variables",
  sprintf("- Outlier slopes (|z| > %.1f): %d", Z_THRESHOLD, nrow(outliers)),
  sprintf("- Structural breaks (p < .05): %d", nrow(significant_breaks)),
  sprintf("- Opposite-direction variable pairs: %d", nrow(opposite_movers)),
  "",
  "## Top Outliers (by |z-score|)",
  if (nrow(outliers) > 0) {
    outliers %>%
      head(10) %>%
      mutate(line = sprintf("- %s | %s: slope = %.3f, z = %.2f (%s)",
                            country, variable, slope, z_slope, direction)) %>%
      pull(line)
  } else "- None found",
  "",
  "## Top Divergent Pairs (variable level)",
  if (nrow(opposite_movers) > 0) {
    opposite_movers %>%
      head(10) %>%
      mutate(line = sprintf("- %s: %s (%s%.3f) vs %s (%s%.3f)",
                            country, var1, direction1, abs(slope1),
                            var2, direction2, abs(slope2))) %>%
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
      sprintf("- Cross-group divergences flagged: %d",
              nrow(cross_group)),
      sprintf("- Cross-group, opposite direction: %d",
              if (nrow(cross_group) > 0) sum(cross_group$opposite) else 0)
    )
  } else "- Concept group analysis not run (no concept_groups.yml found)",
  "",
  "## Top Divergent Concept Groups",
  if (nrow(group_coherence) > 0 &&
      any(group_coherence$coherence_flag == "DIVERGENT")) {
    group_coherence %>%
      filter(coherence_flag == "DIVERGENT") %>%
      arrange(desc(sd_slope)) %>%
      head(10) %>%
      mutate(line = sprintf(
        "- %s | %s: mean slope = %.3f, rising=[%s], falling=[%s]",
        country, group, mean_slope, rising_vars, falling_vars
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
  "## Files",
  sprintf("- %s/outlier_slopes.csv", OUTPUT_DIR),
  sprintf("- %s/structural_breaks.csv", OUTPUT_DIR),
  sprintf("- %s/divergent_pairs.csv", OUTPUT_DIR),
  sprintf("- %s/acceleration.csv", OUTPUT_DIR),
  sprintf("- %s/slope_groups.csv", OUTPUT_DIR),
  sprintf("- %s/slope_divergence.csv", OUTPUT_DIR),
  sprintf("- %s/heatmap_slopes.png", OUTPUT_DIR),
  "",
  "## REMINDER",
  "These are PUZZLES, not findings. Each outlier or divergent group needs:",
  "1. A check of the political timeline — is there a real-world explanation?",
  "2. A check of survey methodology — did sampling/questions change?",
  "3. A theoretical framework — why would this pattern exist?",
  "Only then does it become a paper."
)

writeLines(summary_lines, file.path(OUTPUT_DIR, "prospecting_report.md"))
cat("\n── Summary report saved ──\n")
cat("── Done. Happy prospecting! ──\n")
