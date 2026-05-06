#!/usr/bin/env Rscript
# Plot the tri-survey Korean unification trajectory (KGSS + KINU + IPUS,
# 2003-2025) with annotations for major political events.
#
# Output: outputs/figures/korean_unification_tri_survey.png + .pdf
# Source: data/processed/korean_unification_panel.rds

suppressPackageStartupMessages({
  library(here); library(dplyr); library(ggplot2)
})

panel <- readRDS(here("data/processed/korean_unification_panel.rds"))
cat(sprintf("Panel: %d wave-survey rows\n", nrow(panel)))

events <- tibble::tribble(
  ~year, ~label, ~y,
  2018.75, "Pyongyang Summit (Sep 2018)",      0.78,
  2019.17, "Hanoi Summit failure (Feb 2019)",  0.74,
  2020.50, "Liaison office demolition (Jun 2020)", 0.42,
  2022.25, "Yoon administration (May 2022)",   0.46
)

p <- ggplot(panel, aes(x = decimal_year, y = mean_pro_unif_01,
                       color = survey, group = survey)) +
  # Event markers
  geom_vline(data = events, aes(xintercept = year),
             color = "grey60", linetype = "dotted", linewidth = 0.4) +
  geom_text(data = events, aes(x = year, y = y, label = label),
            inherit.aes = FALSE, hjust = 0, size = 2.7, color = "grey30",
            angle = 0, nudge_x = 0.1) +

  # Series
  geom_line(linewidth = 0.6) +
  geom_point(aes(size = n), alpha = 0.85) +

  scale_color_manual(values = c(kgss = "#1f77b4", kinu = "#d62728", ipus = "#2ca02c"),
                     labels = c(kgss = "KGSS (n≈1,200/yr)",
                                kinu = "KINU (n≈1,000/wave)",
                                ipus = "IPUS (n=1,200/yr)")) +
  scale_size_continuous(range = c(1.2, 3), guide = "none") +
  scale_x_continuous(breaks = seq(2003, 2025, 2), limits = c(2003, 2026)) +
  scale_y_continuous(limits = c(0.4, 0.85), breaks = seq(0.4, 0.85, 0.1)) +

  labs(
    title    = "Korean unification support across three independent surveys, 2003–2025",
    subtitle = "Mean rescaled to 0–1 (higher = stronger belief unification is necessary).\nKGSS pol_unification reversed for direction comparability with KINU and IPUS.",
    x        = NULL,
    y        = "Pro-unification sentiment (rescaled 0–1)",
    color    = "Survey",
    caption  = "Sources: KGSS pol_unification (1–4 reversed); KINU uni_necessity (1–4); IPUS uni_necessity (1–5 reversed).\nKINU 2019–2021 sub-waves shown at fielding-month decimal year. Built via src/scripts/build_korean_unification_panel.R."
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title         = element_text(face = "bold"),
    plot.subtitle      = element_text(color = "grey30", margin = margin(b = 10)),
    plot.caption       = element_text(color = "grey50", size = 8, hjust = 0),
    legend.position    = "top",
    panel.grid.minor   = element_blank()
  )

# Save
out_dir <- here("outputs", "figures")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

png_path <- file.path(out_dir, "korean_unification_tri_survey.png")
pdf_path <- file.path(out_dir, "korean_unification_tri_survey.pdf")

ggsave(png_path, p, width = 10, height = 6, dpi = 200)
ggsave(pdf_path, p, width = 10, height = 6)

cat(sprintf("\nSaved:\n  %s\n  %s\n", png_path, pdf_path))
