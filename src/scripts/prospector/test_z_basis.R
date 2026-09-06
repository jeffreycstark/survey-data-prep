# Tests for the slope z-score basis selector (src/scripts/prospector/z_basis.R).
# Run: Rscript src/scripts/prospector/test_z_basis.R
suppressMessages(library(tidyverse))
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "z_basis.R"))

pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }
near <- function(a, b, tol = 1e-8) all(abs(a - b) < tol)

# ── fixtures ────────────────────────────────────────────────────────────────
multi <- tribble(
  ~country, ~variable, ~slope, ~wave_span,
  "A", "v1",  0.10, 5,
  "B", "v1",  0.20, 5,
  "C", "v1",  0.60, 5,
  "A", "v2", -0.10, 5,
  "B", "v2", -0.10, 5,
  "C", "v2", -0.10, 5
)
# One country, four variables, ALL SPANNING THE SAME WINDOW: with span held
# constant, standardising the slope and standardising the traversal agree.
single <- tribble(
  ~country, ~variable, ~slope, ~wave_span,
  "KOR", "v1",  0.00, 20,
  "KOR", "v2",  0.10, 20,
  "KOR", "v3",  0.20, 20,
  "KOR", "v4",  0.90, 20
)

# ── basis selection ─────────────────────────────────────────────────────────
ok(resolve_z_basis(multi,  "auto") == "cross_country",  "auto -> cross_country when >1 country")
ok(resolve_z_basis(single, "auto") == "cross_variable", "auto -> cross_variable when 1 country")
ok(resolve_z_basis(single, "cross_country") == "cross_country", "explicit basis overrides auto")
ok(tryCatch({ resolve_z_basis(single, "nonsense"); FALSE }, error = function(e) TRUE),
   "unknown basis errors rather than silently defaulting")

# ── cross_country: z within variable, across countries (legacy behaviour) ────
zc <- compute_slope_z(multi, "auto")
ok(all(zc$z_basis == "cross_country"), "multi-country run is labelled cross_country")
ok(all(zc$z_scale == 1) && near(zc$z_input, multi$slope),
   "cross_country standardises the raw slope, unscaled")
v1 <- zc %>% filter(variable == "v1") %>% arrange(country)
ok(near(v1$mean_ref, rep(0.3, 3)), "cross_country reference mean is the per-variable mean")
ok(near(v1$z_slope, (c(0.10, 0.20, 0.60) - 0.3) / sd(c(0.10, 0.20, 0.60))), "cross_country z values")
ok(near(zc$z_slope[zc$variable == "v2"], rep(0, 3)), "zero-variance variable -> z = 0, not NaN")
ok(all(zc$n_ref[zc$variable == "v1"] == 3), "n_ref counts the reference distribution (3 countries)")

# ── cross_variable: z within country, across variables ──────────────────────
zv <- compute_slope_z(single, "auto")
ok(all(zv$z_basis == "cross_variable"), "single-country run is labelled cross_variable")
ok(all(zv$z_scale == 20), "cross_variable scales by each series' wave span")
s <- c(0.00, 0.10, 0.20, 0.90)
ok(near(zv$z_slope, (s - mean(s)) / sd(s)), "with span held constant, z matches the raw-slope z")
ok(all(zv$n_ref == 4), "n_ref counts the 4 variables")
ok(any(abs(zv$z_slope) > 1.4), "an extreme single-country slope actually gets a non-zero z")

# ── the statistic cross_variable uses when respondent SDs are available ─────
# slope x norm_range x wave_span = the raw change over the observed window in the
# item's own units; dividing by a typical respondent-level SD makes items on a
# 1-3 scale and a 0-10 scale directly comparable.
sdful <- tribble(
  ~country, ~variable, ~slope, ~wave_span, ~norm_range, ~sd_typ,
  "KOR", "conf_x",  0.05, 20, 0.20, 0.60,   # 0.20 raw pts over 20y, sd 0.60 -> 0.33 SD
  "KOR", "scale10", 0.05, 20, 2.00, 2.00,   # 2.00 raw pts over 20y, sd 2.00 -> 1.00 SD
  "KOR", "calm1",   0.05, 20, 0.10, 2.00,
  "KOR", "calm2",   0.05, 20, 0.12, 2.00,
  "KOR", "calm3",   0.05, 20, 0.11, 2.00
)
zs <- compute_slope_z(sdful, "cross_variable")
ok(near(zs$z_input, c(1/3, 1, 0.05, 0.06, 0.055) * 1, 1e-6) ||
   near(zs$z_input, sdful$slope * sdful$norm_range * sdful$wave_span / sdful$sd_typ),
   "z_input is the windowed change in respondent-SD units")
ok(zs$variable[which.max(abs(zs$z_slope))] == "scale10",
   "the item that moved furthest in SD units ranks top regardless of its raw scale")
ok(all(zs$z_stat == "sd_units"), "the statistic in use is named in z_stat")

# absent sd_typ -> fall back to traversal, and SAY so rather than pretending
ztrav <- compute_slope_z(sdful %>% select(-sd_typ), "cross_variable")
ok(all(ztrav$z_stat == "traversal"), "without sd_typ the fallback statistic is named traversal")
ok(near(ztrav$z_input, sdful$slope * sdful$wave_span), "traversal fallback is slope x span")

# ── the span bias cross_variable has to correct for ─────────────────────────
# Slopes run on each variable's own min-max-normalized range, so the LARGEST
# slope a series can have is 1/span: a 3-wave/4-year series tops out at 0.25/yr
# while a 17-wave/22-year one tops out at 0.045/yr. Ranking raw slopes across
# variables therefore ranks series length, not movement. Standardising
# traversal (slope x span = share of its own range the series actually covered)
# puts every variable on the same 0-1 ceiling.
mixed <- tribble(
  ~country, ~variable, ~slope, ~wave_span,
  "KOR", "short_flat",  0.20,  4,   # 0.80 of its range over a 4-year window
  "KOR", "long_mover",  0.043, 22,  # 0.95 of its range over a 22-year window
  "KOR", "long_calm1",  0.005, 22,
  "KOR", "long_calm2",  0.004, 22,
  "KOR", "long_calm3",  0.006, 22
)
zm <- compute_slope_z(mixed, "cross_variable")
top <- zm$variable[which.max(abs(zm$z_slope))]
ok(top == "long_mover",
   paste("the variable that traversed most of its range ranks top, not the shortest series (got:", top, ")"))
zm_raw <- compute_slope_z(mixed %>% mutate(wave_span = 1), "cross_variable")
ok(zm_raw$variable[which.max(abs(zm_raw$z_slope))] == "short_flat",
   "control: without the span correction the 4-year series would have won")

ok(tryCatch({ compute_slope_z(single %>% select(-wave_span), "cross_variable"); FALSE },
            error = function(e) grepl("wave_span", conditionMessage(e))),
   "cross_variable without wave_span errors by name instead of silently mis-ranking")
ok(nrow(compute_slope_z(multi %>% select(-wave_span), "cross_country")) == nrow(multi),
   "cross_country does not require wave_span")

# ── the bug this module fixes ───────────────────────────────────────────────
# Under the old cross-country basis a single-country dataset could never
# produce a non-zero z, so outlier detection was structurally empty.
zold <- compute_slope_z(single, "cross_country")
ok(all(zold$z_slope == 0), "cross_country basis on 1 country is degenerate (all z = 0)")
ok(all(zold$n_ref == 1), "n_ref = 1 exposes the degeneracy instead of hiding it")
ok(n_unscoreable(zold) == 4, "n_unscoreable reports how many pairs had no reference distribution")
ok(n_unscoreable(zv) == 0, "nothing unscoreable when the basis has variance")

# ── degenerate: a lone variable under cross_variable ────────────────────────
lone <- tribble(~country, ~variable, ~slope, ~wave_span, "KOR", "v1", 0.5, 10)
zl <- compute_slope_z(lone, "auto")
ok(zl$z_slope == 0 && zl$n_ref == 1, "single variable in a single country -> z = 0, n_ref = 1")

# ── row preservation ────────────────────────────────────────────────────────
ok(nrow(zc) == nrow(multi) && nrow(zv) == nrow(single), "no rows added or dropped")
ok(all(c("z_slope","z_basis","z_input","z_scale","z_stat","n_ref","mean_ref","sd_ref") %in% names(zv)),
   "expected columns present")

# ── direction classification ────────────────────────────────────────────────
# `direction` asks "is this variable moving?". Thresholding the per-wave slope
# answers it in wave units, which differ by survey: 0.05 is 5% of range per 4
# years in ABS and per 1 year in KGSS. The sd_units rule asks the same question
# in respondent SDs across the observed window, which is comparable across both
# scales and series lengths.
dirfix <- tribble(
  ~country, ~variable, ~slope, ~wave_span, ~norm_range, ~sd_typ,
  # the real KGSS case: 1.92 -> 2.89 on a 1-4 scale over 2003-2025.
  "KOR", "pride_social_security", 0.0465, 22, 0.972, 0.72,
  "KOR", "genuinely_flat",        0.0020, 22, 0.100, 0.72,
  "KOR", "falling_fast",         -0.0465, 22, 0.972, 0.72
)
d_slope <- classify_direction(dirfix, "slope", flat_threshold = 0.05)
ok(d_slope[1] == "FLAT", "slope rule: a 1.39 SD shift reads FLAT when its per-year slope is under 0.05")
d_sd <- classify_direction(dirfix, "sd_units", sd_threshold = 0.2)
ok(d_sd[1] == "RISING",  "sd_units rule: the same shift reads RISING")
ok(d_sd[2] == "FLAT",    "sd_units rule: a genuinely small mover still reads FLAT")
ok(d_sd[3] == "FALLING", "sd_units rule: sign is preserved")
ok(near(compute_change_sd(dirfix)[1], 0.0465 * 0.972 * 22 / 0.72),
   "change_sd is slope x norm_range x wave_span / sd_typ")

ok(identical(classify_direction(multi, "slope", flat_threshold = 0.05),
             dplyr::case_when(multi$slope >  0.05 ~ "RISING",
                              multi$slope < -0.05 ~ "FALLING", TRUE ~ "FLAT")),
   "slope rule reproduces the original classification exactly")

ok(tryCatch({ classify_direction(multi %>% select(-norm_range, -sd_typ), "sd_units"); FALSE },
            error = function(e) grepl("sd_typ|norm_range", conditionMessage(e))),
   "sd_units without its inputs errors by column name")
ok(tryCatch({ classify_direction(dirfix, "nonsense"); FALSE }, error = function(e) TRUE),
   "unknown direction basis errors")

zero_sd <- dirfix %>% mutate(sd_typ = c(0, 0.72, 0.72))
ok(classify_direction(zero_sd, "sd_units")[1] == "FLAT",
   "a zero respondent SD yields FLAT, not Inf/NA")

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) quit(status = 1)
