# Paper 3 – Task 5: dem_vs_econ response distribution by wave
# Insert as ```{r dem-vs-econ-dist} in paper3.qmd
# Cambodia (country=12), Waves 2, 3, 4, 6
# Scale: 1=Econ definitely more important → 4=Democracy definitely more important; 5=Both equally
# KEY: 'Both equally' (cat=5) is not on the Econ–Dem continuum; treat as nominal

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(tidyr)
  library(tibble)
})

waves <- c(2, 3, 4, 6)

dem_vs_econ_dist <- bind_rows(lapply(waves, function(w) {
  d     <- readRDS(sprintf("outputs/master_w%d.rds", w)) |> filter(country == 12)
  vals  <- d$dem_vs_econ[!is.na(d$dem_vs_econ)]
  n_v   <- length(vals)
  n_tot <- nrow(d)
  tibble(
    wave      = w,
    cat       = 1:5,
    n         = as.integer(table(factor(vals, levels = 1:5))),
    n_valid   = n_v,
    n_missing = n_tot - n_v,
    pct       = n / n_v * 100
  )
}))

# Wide format for table
dist_wide <- dem_vs_econ_dist |>
  select(wave, cat, pct) |>
  pivot_wider(names_from = wave, values_from = pct, names_prefix = "W") |>
  mutate(label = c("Econ definitely", "Econ somewhat",
                   "Democracy somewhat", "Democracy definitely", "Both equally"))

# Summary: pro-Dem (cats 3+4) vs pro-Econ (cats 1+2) by wave (excluding cat 5)
summary_dist <- dem_vs_econ_dist |>
  mutate(group = case_when(cat %in% 1:2 ~ "pro_econ",
                           cat %in% 3:4 ~ "pro_dem",
                           cat == 5     ~ "both_equal")) |>
  group_by(wave, group) |>
  summarise(pct = sum(pct), .groups = "drop") |>
  pivot_wider(names_from = group, values_from = pct)

# Key findings:
# W3 anomaly: lowest "both equally" (3.6%); highest pro-econ (69.8%)
# Pro-democracy trend: 26.9% (W2) → 26.6% (W3) → 21.0% (W4) → 15.4% (W6)
# "Both equally" balloons: 14.3% (W2) → 3.6% (W3) → 11.3% (W4) → 16.0% (W6)
