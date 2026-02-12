# V-Dem Integration for ABS Paper
# Creates country-year democracy scores to merge with ABS data

# Install if needed: install.packages("vdemdata") or devtools::install_github("vdeminstitute/vdemdata")
library(vdemdata)
library(dplyr)

# Your ABS countries and approximate survey years
abs_countries <- tribble(
  ~country_code, ~country_name, ~vdem_name,
  1, "Japan", "Japan",
  2, "Hong Kong", "Hong Kong",
  3, "Korea", "South Korea",
  4, "China", "China",
  5, "Mongolia", "Mongolia",
  6, "Philippines", "Philippines",
  7, "Taiwan", "Taiwan",
  8, "Thailand", "Thailand",
  9, "Indonesia", "Indonesia",
  10, "Singapore", "Singapore",
  11, "Vietnam", "Vietnam",
  12, "Cambodia", "Cambodia",
  13, "Malaysia", "Malaysia",
  14, "Myanmar", "Burma/Myanmar",
  15, "Australia", "Australia",
  18, "India", "India"
)

# Approximate survey years by wave
wave_years <- tribble(
  ~wave, ~year,
  "w1", 2001,
  "w2", 2005,
  "w3", 2010,
  "w4", 2014,
  "w5", 2018,
  "w6", 2020
)

# Get V-Dem data
vdem <- vdem %>%
  filter(year >= 2000 & year <= 2023) %>%
  select(
    country_name, 
    year,
    # Electoral Democracy Index (0-1)
    v2x_polyarchy,
    # Liberal Democracy Index (0-1)
    v2x_libdem,
    # Regimes of the World (0-3: closed autocracy, electoral autocracy, electoral democracy, liberal democracy)
    v2x_regime,
    # Liberal component
    v2x_liberal,
    # Civil liberties
    v2x_civlib,
    # Freedom of expression
    v2x_freexp_altinf
  )

# Check country name matching
cat("=== V-Dem country names available ===\n")
vdem_countries <- unique(vdem$country_name)
for (c in abs_countries$vdem_name) {
  if (c %in% vdem_countries) {
    cat(c, ": FOUND\n")
  } else {
    cat(c, ": NOT FOUND - need to check spelling\n")
  }
}

# Create lookup table for your ABS data
vdem_lookup <- vdem %>%
  inner_join(abs_countries, by = c("country_name" = "vdem_name")) %>%
  select(country_code, year, v2x_polyarchy, v2x_libdem, v2x_regime) %>%
  rename(
    vdem_electoral = v2x_polyarchy,
    vdem_liberal = v2x_libdem,
    vdem_regime = v2x_regime
  )

# Show scores for your countries at wave midpoints
cat("\n=== V-Dem Electoral Democracy Index by Country-Wave ===\n")
vdem_summary <- vdem_lookup %>%
  filter(year %in% c(2001, 2005, 2010, 2014, 2018, 2020)) %>%
  left_join(abs_countries, by = "country_code") %>%
  select(country_name, year, vdem_electoral, vdem_regime) %>%
  arrange(year, desc(vdem_electoral))

print(as.data.frame(vdem_summary))

# Save for merging
saveRDS(vdem_lookup, "data/external/vdem_scores.rds")

# Regime classification based on V-Dem
# 0 = Closed Autocracy, 1 = Electoral Autocracy, 2 = Electoral Democracy, 3 = Liberal Democracy
cat("\n=== Regime Classifications ===\n")
cat("0 = Closed Autocracy\n")
cat("1 = Electoral Autocracy\n") 
cat("2 = Electoral Democracy\n")
cat("3 = Liberal Democracy\n")
