# Feature builders for the Slope Prospector signature matcher.
suppressMessages({ library(tidyverse); library(strucchange) })

# Estimate the wave at which each significant break occurs.
augment_breaks_with_location <- function(eligible, sig_breaks) {
  targets <- eligible %>% semi_join(sig_breaks, by = c("country","variable"))
  if (nrow(targets) == 0)
    return(tibble(country=character(), variable=character(), break_wave=numeric()))
  targets %>%
    group_by(country, variable) %>%
    group_modify(~ {
      ts <- .x %>% arrange(wave_num)
      wave <- tryCatch({
        bp <- strucchange::breakpoints(mean_value ~ wave_num, data = ts, h = 3)
        idx <- bp$breakpoints
        if (length(idx) == 0 || all(is.na(idx))) NA_real_ else ts$wave_num[idx[1]]
      }, error = function(e) NA_real_)
      tibble(break_wave = wave)
    }) %>%
    ungroup()
}
