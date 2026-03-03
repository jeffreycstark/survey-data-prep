# Paper 3 – Task 4: SAIE 2017 appendix table with Wilson 95% CIs
# Insert as ```{r saie-table} in paper3.qmd
# Data: KHM_2018_SAIE (fieldwork inferred early-mid 2017; deposited 2018)
# Variables: Q2_39–Q2_44 (Agree/Disagree binary)
# Note: Governance module not fielded in SAIE 2018–2020

suppressPackageStartupMessages({
  library(haven)
  library(dplyr)
  library(tibble)
})

path <- "data/cses/KHM_2018_SAIE_v01_M_SPSS/isaf_hhq_main_clean_de_identified_12_nd.sav"
d <- read_sav(path, encoding = "latin1")

# Wilson CI for binary proportion (Agree=1, Disagree=2; missing = -99 or NA)
wilson_ci <- function(n_agree, n_valid, conf = 0.95) {
  z     <- qnorm((1 + conf) / 2)
  p_hat <- n_agree / n_valid
  ctr   <- (n_agree + z^2 / 2) / (n_valid + z^2)
  marg  <- z * sqrt(p_hat * (1 - p_hat) / n_valid + z^2 / (4 * n_valid^2)) /
           (1 + z^2 / n_valid)
  c(p = p_hat, lo = ctr - marg, hi = ctr + marg)
}

q_wording <- c(
  Q2_39 = "Commune councillors generally helpful and responsive",
  Q2_40 = "Village chief works for the benefit of citizens",
  Q2_41 = "People free to speak what they think without fear",
  Q2_42 = "People free to join any organisation without fear",
  Q2_43 = "People free to vote for any political party",
  Q2_44 = "Paid additional money to officials to get things done faster (2016)"
)

saie_table <- bind_rows(lapply(paste0("Q2_", 39:44), function(v) {
  valid  <- d[[v]][d[[v]] %in% c(1, 2)]
  n_v    <- length(valid)
  n_a    <- sum(valid == 1)
  wi     <- wilson_ci(n_a, n_v)
  tibble(
    variable   = v,
    wording    = q_wording[v],
    n_valid    = n_v,
    pct_agree  = round(wi["p"]  * 100, 1),
    ci_lo      = round(wi["lo"] * 100, 1),
    ci_hi      = round(wi["hi"] * 100, 1)
  )
}))

# Results:
# Q2_39: 88.2% [87.0, 89.2]  — councillors helpful
# Q2_40: 89.4% [88.3, 90.4]  — village chief works for citizens
# Q2_41: 86.1% [84.9, 87.2]  — free to speak
# Q2_42: 87.9% [86.7, 88.9]  — free to join organisations
# Q2_43: 94.0% [93.1, 94.7]  — free to vote for any party
# Q2_44: 34.9% [33.3, 36.5]  — PAID EXTRA TO OFFICIALS (bribery)

saveRDS(saie_table, "data/processed/tableD_saie_governance.rds")
cat("Saved: data/processed/tableD_saie_governance.rds\n")
