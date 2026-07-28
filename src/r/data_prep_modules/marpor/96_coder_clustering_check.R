# Paper 25 TASK 1 open question:
#   "The measurement-error correction assumes BLM standard errors are
#    independent across parties within an election. Manifestos in one election
#    often share a coder... If within-election SE correlation is material the
#    correction will UNDER-correct."
#
# Answering three separable things, because they are NOT the same question:
#   (a) do parties within an election actually share coders?
#   (b) is rile_se clustered within election / within coder?
#   (c) does that clustering survive controlling for manifesto length, which
#       mechanically drives the BLM SE (SE ~ 1/sqrt(N quasi-sentences))?

suppressPackageStartupMessages({ library(dplyr); library(here) })

a  <- readRDS(here("data", "processed", "marpor_party_election.rds"))
se <- readRDS(here("data", "processed", "marpor_manifesto_se.rds"))

d <- se %>%
  left_join(a %>% select(party, edate, coderid, manual, coderyear, testresult),
            by = c("party", "edate")) %>%
  mutate(elec = paste(countryname, edate))

cat(sprintf("manifestos: %d | elections: %d | coderid present: %.1f%%\n",
            nrow(d), n_distinct(d$elec), 100*mean(!is.na(d$coderid))))

# ── (a) coder sharing within elections ──────────────────────────────────────
sh <- d %>% filter(!is.na(coderid)) %>%
  group_by(elec) %>%
  summarise(n_man = n(), n_coders = n_distinct(coderid), .groups = "drop") %>%
  filter(n_man >= 2)
cat("\n(a) COAUTHORSHIP OF CODING WITHIN AN ELECTION\n")
cat(sprintf("    elections with >=2 manifestos: %d\n", nrow(sh)))
cat(sprintf("    ALL manifestos share ONE coder : %d (%.1f%%)\n",
            sum(sh$n_coders == 1), 100*mean(sh$n_coders == 1)))
cat(sprintf("    median coders per election     : %.1f (median manifestos %.1f)\n",
            median(sh$n_coders), median(sh$n_man)))

# ── (b) ICC of rile_se, by election and by coder ────────────────────────────
# ICC via one-way ANOVA decomposition: between-group variance share.
icc <- function(x, g) {
  k <- !is.na(x) & !is.na(g)
  x <- x[k]; g <- factor(g[k])
  if (nlevels(g) < 2) return(NA_real_)
  fit <- stats::aov(x ~ g)
  ms  <- summary(fit)[[1]][["Mean Sq"]]
  df  <- summary(fit)[[1]][["Df"]]
  n0  <- (sum(table(g)) - sum(table(g)^2)/sum(table(g))) / df[1]
  vb  <- max(0, (ms[1] - ms[2]) / n0)
  vb / (vb + ms[2])
}

cat("\n(b) CLUSTERING OF rile_se (raw)\n")
cat(sprintf("    ICC by election : %.3f\n", icc(d$rile_se, d$elec)))
cat(sprintf("    ICC by coderid  : %.3f\n", icc(d$rile_se, d$coderid)))

# ── (c) does it survive length? ─────────────────────────────────────────────
# BLM SE is mechanically ~ 1/sqrt(n_accounted). Manifesto length is correlated
# within an election (same campaign, same era, same document conventions), so a
# raw ICC will look large even with zero coder effect. Residualize first.
d2 <- d %>% filter(is.finite(rile_se), rile_se > 0, n_accounted > 0)
m  <- lm(log(rile_se) ~ log(n_accounted), data = d2)
d2$resid <- resid(m)
cat(sprintf("\n(c) AFTER REMOVING LENGTH (log-log R2 = %.3f)\n", summary(m)$r.squared))
cat(sprintf("    residual ICC by election : %.3f\n", icc(d2$resid, d2$elec)))
cat(sprintf("    residual ICC by coderid  : %.3f\n", icc(d2$resid, d2$coderid)))

# restricted to the elections the paper actually uses (>=3 RILE-bearing parties)
d3 <- d2 %>% filter(!is.na(rile)) %>% group_by(elec) %>% filter(n() >= 3) %>% ungroup()
cat(sprintf("\n    [restricted to elections with >=3 RILE-bearing parties: %d manifestos, %d elections]\n",
            nrow(d3), n_distinct(d3$elec)))
cat(sprintf("    residual ICC by election : %.3f\n", icc(d3$resid, d3$elec)))
cat(sprintf("    residual ICC by coderid  : %.3f\n", icc(d3$resid, d3$coderid)))
