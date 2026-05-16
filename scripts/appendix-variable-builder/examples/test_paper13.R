#' Regression test: regenerate paper 13's Survey Items section.
#'
#' Run with:
#'   Rscript scripts/appendix-variable-builder/examples/test_paper13.R
#'
#' Writes the generated markdown to /tmp/paper13_generated_appendix.md and
#' prints a summary diff against the hand-written reference. The two won't
#' match byte-for-byte (the generator pulls more harmonization detail from
#' the YAML than the hand-written version surfaces) but the per-wave QID
#' grids must match exactly.

suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(stringr)
})

source(here::here("scripts", "appendix-variable-builder", "build_appendix.R"))
source(here::here("scripts", "appendix-variable-builder", "examples", "paper13_spec.R"))

out_path <- "/tmp/paper13_generated_appendix.md"

md <- build_appendix(
  survey      = "abs",
  groups      = paper13_groups,
  title       = "Survey Items",
  intro       = paper13_intro,
  output_file = out_path
)

# ---- Regression: per-wave QID grids must match paper 13's hand-written ----

# Pull every "Wave QIDs: ..." line from the generated output
generated_qids <- str_match_all(md, "\\*\\*Wave QIDs:\\*\\* ([^.]+)\\.")[[1]][, 2]
generated_qids <- trimws(generated_qids)

# Reference: pulled by inspection from aa-online-appendix.qmd Survey Items section
reference_qids <- c(
  "W1 q121, W2 q124, W3 q129, W4 q130, W5 q137, W6 q129",  # strongman_rule
  "W1 q123, W2 q126, W3 q131, W4 q132, W5 q139, W6 q131",  # military_rule
  "W1 q122, W2 q125, W3 q130, W4 q131, W5 q138, W6 q130",  # single_party_rule
  "W1 q098, W2 q93, W3 q89, W4 q92, W5 q99, W6 q90",        # democracy_satisfaction
  "W1 q008, W2 q9, W3 q9, W4 q9, W5 q9, W6 q9",             # trust_national_government (paper 13: "W1 q008, W2-W6 q9")
  "W1 q115, W2 q118, W3 q117, W4 q118, W5 q125, W6 q116",   # corrupt_national_govt
  "W1 q001, W2 q1, W3 q1, W4 q1, W5 q1, W6 q1",             # econ_national_now (paper 13: "W1-W6 q1")
  "W3 q92, W4 q95, W5 q102, W6 q93",                         # dem_country_past
  "W1 q100, W2 q96, W3 q91, W4 q94, W5 q101, W6 q92",        # dem_country_present_govt
  "W1 q117, W2 q121, W3 q124, W4 q125, W5 q132, W6 q124",    # dem_always_preferable
  "W1 q103, W2 q98, W3 q94, W4 q97, W5 q104, W6 q95",        # democracy_suitability
  "W1 q118, W2 q122, W3 q125, W4 q126, W5 q133, W6 q125",    # democracy_efficacy
  "W1 q134, W2 q135, W3 q142, W4 q143, W5 q150, W6 q150",    # auth_govt_censor_ideas
  "W1 q136, W2 q137, W3 q144, W4 q145, W5 q152, W6 q152"     # auth_judges_defer_executive
)

n_match <- sum(generated_qids %in% reference_qids)
n_total <- length(reference_qids)

cat("\n=========== regression test ===========\n")
cat("Wave QID lines matching paper 13 reference: ", n_match, "/", n_total, "\n", sep = "")

if (n_match < n_total) {
  cat("\nMissing or differing lines:\n")
  for (r in reference_qids) {
    if (!r %in% generated_qids) cat("  - expected: ", r, "\n", sep = "")
  }
  cat("\nGenerator produced these instead:\n")
  for (g in generated_qids) {
    if (!g %in% reference_qids) cat("  - got:      ", g, "\n", sep = "")
  }
  quit(status = 1)
}

cat("\nAll wave QID grids match paper 13's hand-written reference.\n")
cat("Generated markdown:", out_path, "\n")
