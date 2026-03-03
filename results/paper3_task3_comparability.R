# Paper 3 – Task 3: Comparability matrix (Table A1 extended)
# Insert as ```{r comparability-matrix} or as a kable table in paper3.qmd
# Covers: dem_always_preferable, dem_best_form, dem_vs_econ,
#         dem_vs_equality, democracy_satisfaction
# Waves: W2, W3, W4, W6 (Cambodia)

# Source variable numbers from src/config/abs/harmonize_validated/democracy.yml
# Raw SPSS labels confirmed by reading wave files with haven::read_sav()

comparability <- tibble::tribble(
  ~variable,               ~wave, ~q_number, ~wording_note,                                ~raw_scale,                           ~harmonized_scale,                   ~status,
  "dem_always_preferable", "W2",  "q121",    "Identical wording; response ORDER differs",  "1=Doesn't matter; 2=Auth; 3=Dem",    "1=Dem always; 2=Auth; 3=Doesn't matter", "RECODED",
  "dem_always_preferable", "W3",  "q124",    "Canonical wording",                          "1=Dem always; 2=Auth; 3=Doesn't",    "Identity",                               "COMPARABLE",
  "dem_always_preferable", "W4",  "q125",    "Identical to W3",                            "Same as W3",                          "Identity",                               "COMPARABLE",
  "dem_always_preferable", "W6",  "q124",    "Identical to W3",                            "Same as W3",                          "Identity",                               "COMPARABLE",

  "dem_best_form",         "W2",  "—",       "Not asked",                                  "—",                                   "—",                                      "ABSENT",
  "dem_best_form",         "W3",  "q128",    "Canonical wording",                          "1=Str agree; 2=Agree; 3=Disagree; 4=Str disagree", "REVERSED: 4=Str agree … 1=Str disagree", "RECODED",
  "dem_best_form",         "W4",  "q129",    "Identical to W3",                            "Same as W3",                          "REVERSED (same as W3)",                  "COMPARABLE",
  "dem_best_form",         "W6",  "q128",    "Minor punctuation diff.; identical substance","Same as W3",                          "REVERSED (same as W3)",                  "COMPARABLE",

  "dem_vs_econ",           "W2",  "q123",    "Canonical wording",                          "1=Econ def; 2=Econ some; 3=Dem some; 4=Dem def; 5=Both", "Identity",            "COMPARABLE",
  "dem_vs_econ",           "W3",  "q126",    "Identical to W2",                            "Same as W2",                          "Identity",                               "COMPARABLE",
  "dem_vs_econ",           "W4",  "q127",    "Identical to W2",                            "Same as W2",                          "Identity",                               "COMPARABLE",
  "dem_vs_econ",           "W6",  "q126",    "Minor 'Don't' vs 'Do not'; identical",       "Same as W2",                          "Identity",                               "COMPARABLE",

  "dem_vs_equality",       "W2",  "—",       "Not asked",                                  "—",                                   "—",                                      "ABSENT",
  "dem_vs_equality",       "W3",  "q127",    "Canonical wording",                          "1=Ineq def; 2=Ineq some; 3=Free some; 4=Free def; 5=Both", "REMAPPED: 5→3 center", "RECODED",
  "dem_vs_equality",       "W4",  "q128",    "Identical to W3",                            "Same as W3",                          "Same remapping",                         "COMPARABLE",
  "dem_vs_equality",       "W6",  "q127",    "Minor 'Don't' vs 'Do not'; identical",       "Same as W3",                          "Same remapping",                         "COMPARABLE",

  "democracy_satisfaction","W2",  "q93",     "Canonical wording",                          "1=Not at all; 2=Not very; 3=Fairly; 4=Very satisfied", "Identity",              "COMPARABLE",
  "democracy_satisfaction","W3",  "q89",     "Identical substance; encoding artifact in label","1=Very satisfied; 2=Fairly; 3=Not very; 4=Not at all", "REVERSED: 4=Very … 1=Not at all", "RECODED",
  "democracy_satisfaction","W4",  "q92",     "Identical to W3",                            "Same as W3",                          "REVERSED (same as W3)",                  "COMPARABLE",
  "democracy_satisfaction","W6",  "q90",     "Identical to W3",                            "Same as W3",                          "REVERSED (same as W3)",                  "COMPARABLE"
)

# For a kable table in .qmd:
# knitr::kable(comparability, caption = "Table A1: Question comparability matrix, Cambodia ABS W2–W6")
