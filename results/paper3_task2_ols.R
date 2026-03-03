# Paper 3 – Task 2: OLS regression table
# Insert as ```{r ols-regression} in paper3.qmd
# 5 outcomes × wave dummies (W3 ref) + age group + education + urban/rural
# Cambodia only (country=12); pooled W2+W3+W4+W6

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
})

# --- Load and pool ---
load_khm <- function(w) {
  readRDS(sprintf("outputs/master_w%d.rds", w)) |>
    filter(country == 12) |>
    mutate(wave = w)
}

need <- c("wave", "dem_country_future", "dem_vs_equality", "dem_always_preferable",
          "democracy_satisfaction", "gate_contact_influential",
          "age", "gender", "education_level", "urban_rural")

pool <- bind_rows(lapply(list(load_khm(2), load_khm(3), load_khm(4), load_khm(6)),
                         function(d) {
                           for (v in need) if (!v %in% names(d)) d[[v]] <- NA_real_
                           d[, need]
                         })) |>
  mutate(
    # Age groups: reference = under 30
    age_grp = factor(
      case_when(age < 30             ~ "under30",
                age >= 30 & age < 50 ~ "30to49",
                age >= 50            ~ "50plus",
                TRUE                 ~ NA_character_),
      levels = c("under30", "30to49", "50plus")),
    # Education: primary (1–3) ref; secondary (4–7); tertiary (8–10)
    edu_grp = factor(
      case_when(education_level %in% 1:3  ~ "primary",
                education_level %in% 4:7  ~ "secondary",
                education_level %in% 8:10 ~ "tertiary",
                TRUE                      ~ NA_character_),
      levels = c("primary", "secondary", "tertiary")),
    # Urban/rural: 0=Rural (ref), 1=Urban
    urban  = factor(urban_rural, levels = c(0, 1), labels = c("Rural", "Urban")),
    # Wave factor: W3 reference
    wave_f = relevel(factor(wave), ref = "3")
  )

# --- Run models ---
outcomes <- c("dem_country_future", "dem_vs_equality", "dem_always_preferable",
              "democracy_satisfaction", "gate_contact_influential")

models <- lapply(setNames(outcomes, outcomes), function(out) {
  dat <- pool |> filter(!is.na(.data[[out]]))
  lm(as.formula(sprintf("%s ~ wave_f + age_grp + edu_grp + urban", out)), data = dat)
})

# Key results (wave coefficients, SEs, p-values):
# Wave 4 vs W3: dem_country_future = -1.86***, democracy_satisfaction = -0.27***
# Wave 6 vs W3: dem_country_future = -2.89***, gate_contact_influential = -0.30***
# R² modest (0.03–0.24); wave dummies dominate
#
# Reference categories: Wave 3, Age under-30, Education primary, Rural
# Note: dem_country_future and dem_vs_equality have no W2 data → Wave 2 coef = NA for those
