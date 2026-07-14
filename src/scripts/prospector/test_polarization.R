suppressMessages(library(tidyverse))
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "polarization.R"))
pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) pass <<- pass + 1L else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

# Synthetic: mean flat + sd rising = POLARIZING; mean flat + sd falling =
# DEPOLARIZING; mean shifting + sd flat = OTHER.
df <- bind_rows(
  tibble(country="Z", variable="v_pol",   wave_num=1:4, mean_value=0.5,            sd_value=c(.1,.3,.5,.7), n=100),
  tibble(country="Z", variable="v_depol", wave_num=1:4, mean_value=0.5,            sd_value=c(.7,.5,.3,.1), n=100),
  tibble(country="Z", variable="v_shift", wave_num=1:4, mean_value=c(.2,.4,.6,.8), sd_value=0.3,            n=100)
)
out <- detect_polarization(df, min_waves=3, flat_threshold=0.05)

ok(out$pattern[out$variable=="v_pol"]   == "POLARIZING",   "flat mean + rising sd -> POLARIZING")
ok(out$pattern[out$variable=="v_depol"] == "DEPOLARIZING", "flat mean + falling sd -> DEPOLARIZING")
ok(out$pattern[out$variable=="v_shift"] == "OTHER",        "shifting mean + flat sd -> OTHER (not polarization)")
ok(out$sd_slope[out$variable=="v_pol"]  > 0.05,            "v_pol sd_slope is positive and past flat threshold")
ok(abs(out$mean_slope[out$variable=="v_pol"]) <= 0.05,     "v_pol mean_slope is flat")

# min_waves gate: a 2-wave variable is dropped
df2 <- tibble(country="Z", variable="short", wave_num=1:2, mean_value=0.5, sd_value=c(.1,.5), n=100)
ok(nrow(detect_polarization(df2, min_waves=3)) == 0, "variable with < min_waves is dropped")

# NA-safe: sd_value NA rows are ignored, mean series still fit
df3 <- df %>% mutate(sd_value = if_else(variable=="v_pol" & wave_num==1, NA_real_, sd_value))
out3 <- detect_polarization(df3, min_waves=3)
ok(nrow(out3) == 3 && "v_pol" %in% out3$variable,
   "NA sd row dropped but v_pol keeps 3 valid waves and still classifies")

# ── detect_sorting: subgroup-gap widening/narrowing ──
gaps <- bind_rows(
  tibble(country="Z", variable="v_widen",  wave_num=1:4, gap=c(.1,.2,.3,.4), n=100),
  tibble(country="Z", variable="v_narrow", wave_num=1:4, gap=c(.4,.3,.2,.1), n=100),
  tibble(country="Z", variable="v_flat",   wave_num=1:4, gap=0.2,            n=100)
)
srt <- detect_sorting(gaps, min_waves=3, flat_threshold=0.05)
ok(srt$pattern[srt$variable=="v_widen"]  == "WIDENING",  "growing subgroup gap -> WIDENING")
ok(srt$pattern[srt$variable=="v_narrow"] == "NARROWING", "shrinking subgroup gap -> NARROWING")
ok(srt$pattern[srt$variable=="v_flat"]   == "OTHER",     "constant subgroup gap -> OTHER")
# sorting keys on |gap|, so a negative gap widening (more negative) also WIDENS
gaps2 <- tibble(country="Z", variable="v_neg", wave_num=1:4, gap=c(-.1,-.2,-.3,-.4), n=100)
ok(detect_sorting(gaps2, min_waves=3)$pattern == "WIDENING", "gap growing more negative -> WIDENING (|gap| based)")

# ── Pass C2: van der Eijk's A statistic ──
ok(abs(.vdeijk_A(c(100, 0, 0))    - 1) < 1e-9, "A=+1 all mass one category (K=3)")
ok(abs(.vdeijk_A(c(0, 100, 0))    - 1) < 1e-9, "A=+1 all mass centre category (K=3)")
ok(abs(.vdeijk_A(c(50, 50, 50))   - 0) < 1e-9, "A=0 uniform (K=3)")
ok(abs(.vdeijk_A(c(50, 0, 50))    + 1) < 1e-9, "A=-1 split at extremes (K=3)")
ok(abs(.vdeijk_A(c(50, 0, 0, 50)) + 1) < 1e-9, "A=-1 split at extremes (K=4)")
ok(.vdeijk_A(c(10, 80, 10)) > 0,               "unimodal hump -> positive A")
ok(is.na(.vdeijk_A(c(0, 0, 0))),               "no responses -> NA")

# ── Pass C2: per-wave A table ──
frq_bw <- bind_rows(
  tibble(country="Z", variable="v", wave_num=1, value=3,        count=100),           # centre spike -> A=1
  tibble(country="Z", variable="v", wave_num=2, value=c(1,5),   count=c(50,50)),       # extremes    -> A=-1
  tibble(country="Z", variable="v", wave_num=3, value=c(1,2,3), count=c(10,80,10))     # only codes 1..3 seen this wave
)
bw <- .bimodality_by_wave(frq_bw)
ok(nrow(bw) == 3,                                           "one row per country x wave x variable")
ok(all(bw$K == 5),                                          "K = observed span 1..5 across all waves (fixed per variable)")
ok(abs(bw$A[bw$wave_num==1] - 1) < 1e-9,                    "centre spike wave -> A=1")
ok(abs(bw$A[bw$wave_num==2] + 1) < 1e-9,                    "extremes wave -> A=-1")
ok(bw$n[bw$wave_num==2] == 100,                             "n = total responses in the cell")

# integer-code guard: a fractional-valued variable is dropped
frq_frac <- tibble(country="Z", variable="v01", wave_num=1:3, value=c(0, 0.5, 1), count=100)
ok(nrow(.bimodality_by_wave(frq_frac)) == 0,               "non-integer-coded variable dropped")

# ── Pass C2: detect_bimodality classification ──
frq_split <- bind_rows(   # unimodal centre -> split extremes over 4 waves
  tibble(country="Z", variable="v_split", wave_num=1, value=3,            count=100),
  tibble(country="Z", variable="v_split", wave_num=2, value=c(2,3,4),     count=c(20,60,20)),
  tibble(country="Z", variable="v_split", wave_num=3, value=c(1,3,5),     count=c(30,40,30)),
  tibble(country="Z", variable="v_split", wave_num=4, value=c(1,5),       count=c(50,50))
)
frq_conv <- bind_rows(    # split extremes -> unimodal centre (reverse)
  tibble(country="Z", variable="v_conv", wave_num=1, value=c(1,5),        count=c(50,50)),
  tibble(country="Z", variable="v_conv", wave_num=2, value=c(1,3,5),      count=c(30,40,30)),
  tibble(country="Z", variable="v_conv", wave_num=3, value=c(2,3,4),      count=c(20,60,20)),
  tibble(country="Z", variable="v_conv", wave_num=4, value=3,            count=100)
)
frq_shift <- bind_rows(   # unimodal throughout but the MODE shifts (mean moves)
  tibble(country="Z", variable="v_shift2", wave_num=1, value=1, count=100),
  tibble(country="Z", variable="v_shift2", wave_num=2, value=2, count=100),
  tibble(country="Z", variable="v_shift2", wave_num=3, value=3, count=100),
  tibble(country="Z", variable="v_shift2", wave_num=4, value=4, count=100)
)
frq_bin <- bind_rows(     # K=2 -> excluded
  tibble(country="Z", variable="v_bin", wave_num=1:4, value=1, count=60),
  tibble(country="Z", variable="v_bin", wave_num=1:4, value=2, count=40)
)
frq_wide <- bind_rows(    # K=20 -> excluded by max_categories (quasi-continuous)
  tibble(country="Z", variable="v_wide", wave_num=1, value=10,          count=100),
  tibble(country="Z", variable="v_wide", wave_num=2, value=c(5,15),     count=c(50,50)),
  tibble(country="Z", variable="v_wide", wave_num=3, value=c(1,20),     count=c(50,50))
)
frq_c2 <- bind_rows(frq_split, frq_conv, frq_shift, frq_bin, frq_wide)
bm <- detect_bimodality(frq_c2, min_waves=3, flat_threshold=0.05, bimodal_A_max=0.5, max_categories=11)

ok(bm$pattern[bm$variable=="v_split"] == "POLARIZING_BIMODAL",  "unimodal->bimodal -> POLARIZING_BIMODAL")
ok(bm$pattern[bm$variable=="v_conv"]  == "CONVERGING_UNIMODAL", "bimodal->unimodal -> CONVERGING_UNIMODAL")
ok(bm$pattern[bm$variable=="v_shift2"] == "OTHER",             "shifting-but-unimodal -> OTHER (not a mean re-detect)")
ok(!("v_bin" %in% bm$variable),                                "K<3 variable excluded")
ok(!("v_wide" %in% bm$variable),                               "K>max_categories variable excluded")
ok(all(is.na(bm$c1a_pattern)),                                 "c1a_pattern NA when no polarization.csv")

# guard: with an unreachable bimodal_A_max, a rising-pol item is NOT called bimodal
bm_g <- detect_bimodality(frq_split, min_waves=3, flat_threshold=0.05, bimodal_A_max=-2)
ok(bm_g$pattern[bm_g$variable=="v_split"] == "OTHER",          "A_end guard blocks POLARIZING_BIMODAL")

# min_waves gate
frq_short <- bind_rows(
  tibble(country="Z", variable="v_sh", wave_num=1, value=3,      count=100),
  tibble(country="Z", variable="v_sh", wave_num=2, value=c(1,5), count=c(50,50))
)
ok(nrow(detect_bimodality(frq_short, min_waves=3)) == 0,       "variable with < min_waves dropped")

# c1a_pattern join when polarization.csv is present
td <- tempfile("c2_"); dir.create(td)
readr::write_csv(tibble(country="Z", variable="v_split", pattern="POLARIZING"),
                 file.path(td, "polarization.csv"))
bm_j <- detect_bimodality(frq_split, out_dir=td, min_waves=3)
ok(bm_j$c1a_pattern[bm_j$variable=="v_split"] == "POLARIZING", "c1a_pattern joined from polarization.csv")
ok(file.exists(file.path(td, "bimodality.csv")),              "bimodality.csv written to out_dir")

cat(sprintf("\n%d passed, %d failed\n", pass, fail)); if (fail > 0) quit(status = 1)
