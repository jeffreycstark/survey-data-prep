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

cat(sprintf("\n%d passed, %d failed\n", pass, fail)); if (fail > 0) quit(status = 1)
