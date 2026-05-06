#!/usr/bin/env Rscript
# Build a tri-survey Korean unification opinion panel by combining the three
# harmonized surveys into one long-format dataset.
#
# Output: data/processed/korean_unification_panel.{rds,parquet}
#
# DIRECTION ALIGNMENT.
#   IPUS uni_necessity:  raw 1-5 reversed in harmonization → higher = pro-unification ✓
#   KINU uni_necessity:  raw 1-4 identity → higher = pro-unification ✓
#   KGSS pol_unification: raw 1-4 identity → higher = LESS pro-unification (OPPOSITE!)
#                         => reverse here so the panel is direction-consistent.
# After alignment, all three columns are interpretable as "intensity of belief
# that unification is necessary": higher = stronger pro-unification.

suppressPackageStartupMessages({
  library(here); library(dplyr); library(arrow)
})

cat("Loading harmonized datasets...\n")
kgss <- readRDS(here("data/processed/kgss_harmonized.rds"))
kinu <- readRDS(here("data/processed/kinu_harmonized.rds"))
ipus <- readRDS(here("data/processed/ipus_harmonized.rds"))

cat(sprintf("  kgss: %s rows × %d cols\n", format(nrow(kgss), big.mark=","), ncol(kgss)))
cat(sprintf("  kinu: %s rows × %d cols\n", format(nrow(kinu), big.mark=","), ncol(kinu)))
cat(sprintf("  ipus: %s rows × %d cols\n", format(nrow(ipus), big.mark=","), ncol(ipus)))

# ── KGSS: pol_unification (1-4 identity → REVERSE for panel) ───────────────────
kgss_panel <- kgss %>%
  filter(!is.na(pol_unification)) %>%
  mutate(pro_unif = 5 - pol_unification) %>%
  group_by(year) %>%
  summarise(
    mean_pro_unif = mean(pro_unif, na.rm = TRUE),
    n             = sum(!is.na(pro_unif)),
    sd            = sd(pro_unif, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  mutate(
    survey          = "kgss",
    fieldwork_month = NA_integer_,
    wave_label      = as.character(year),
    raw_var         = "pol_unification (reversed)",
    item_text       = "Necessity of Korean unification (KGSS)",
    scale_min       = 1L,
    scale_max       = 4L
  )

# ── KINU: uni_necessity (1-4 identity, higher=pro) ──────────────────────────
kinu_panel <- kinu %>%
  filter(!is.na(uni_necessity)) %>%
  group_by(wave, year, fieldwork_month) %>%
  summarise(
    mean_pro_unif = mean(uni_necessity, na.rm = TRUE),
    n             = sum(!is.na(uni_necessity)),
    sd            = sd(uni_necessity, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  mutate(
    survey      = "kinu",
    wave_label  = as.character(wave),
    raw_var     = "uni_necessity (uni01 / uni01_a)",
    item_text   = "Necessity of Korean unification (KINU)",
    scale_min   = 1L,
    scale_max   = 4L
  ) %>%
  select(-wave)

# ── IPUS: uni_necessity (1-5 REVERSED, higher=pro) ──────────────────────────
ipus_panel <- ipus %>%
  filter(!is.na(uni_necessity)) %>%
  group_by(year) %>%
  summarise(
    mean_pro_unif = mean(uni_necessity, na.rm = TRUE),
    n             = sum(!is.na(uni_necessity)),
    sd            = sd(uni_necessity, na.rm = TRUE),
    .groups       = "drop"
  ) %>%
  mutate(
    survey          = "ipus",
    fieldwork_month = NA_integer_,
    wave_label      = as.character(year),
    raw_var         = "uni_necessity (a12 / b06 / uni01 / uni01_a, reversed)",
    item_text       = "Necessity of Korean unification (IPUS)",
    scale_min       = 1L,
    scale_max       = 5L
  )

# ── Combine + add convenience columns ─────────────────────────────────────────
panel <- bind_rows(kgss_panel, kinu_panel, ipus_panel) %>%
  mutate(
    decimal_year     = year + (ifelse(is.na(fieldwork_month), 6.5, fieldwork_month) - 6.5) / 12,
    mean_pro_unif_01 = (mean_pro_unif - scale_min) / (scale_max - scale_min)
  ) %>%
  select(survey, year, fieldwork_month, decimal_year, wave_label, raw_var,
         item_text, scale_min, scale_max, mean_pro_unif, mean_pro_unif_01,
         n, sd) %>%
  arrange(survey, decimal_year)

cat(sprintf("\nPanel: %d rows (%d kgss + %d kinu + %d ipus)\n",
            nrow(panel),
            sum(panel$survey == "kgss"),
            sum(panel$survey == "kinu"),
            sum(panel$survey == "ipus")))

dir.create(here("data", "processed"), showWarnings = FALSE, recursive = TRUE)
rds_path <- here("data", "processed", "korean_unification_panel.rds")
pq_path  <- here("data", "processed", "korean_unification_panel.parquet")

saveRDS(panel, rds_path)
arrow::write_parquet(panel, pq_path)
cat(sprintf("\nSaved:\n  %s\n  %s\n", rds_path, pq_path))

cat("\nPer-survey summary:\n")
print(panel %>%
        group_by(survey) %>%
        summarise(
          first_year   = min(year),
          last_year    = max(year),
          n_waves      = n(),
          mean_overall = round(mean(mean_pro_unif_01), 3),
          .groups      = "drop"
        ))

cat("\nAll waves (rescaled 0-1):\n")
print(panel %>%
        select(survey, year, fieldwork_month, mean_pro_unif_01, n) %>%
        arrange(year, fieldwork_month, survey),
      n = 60)
