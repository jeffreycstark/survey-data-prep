#!/usr/bin/env Rscript
# Build KINU verbatim question dictionary from the codebook XLSX.
#
# Source: data/kinu/raw/kinu_2014-2024_codebook_en.xlsx
# Output: data/kinu/questionnaire_text/kinu_verbatim_items.csv
#
# Optional alias file: data/kinu/questionnaire_text/raw_to_harmonized.csv
#   Two columns: raw_variable, harmonized_name. If present, fills the
#   harmonized_name column; otherwise harmonized_name = raw variable name.
#
# The codebook is column-cross-referenced: one row per raw variable, one
# wave-presence column per fielding (14, 15, 16, 17, 18, 19a, 19b, 20a, 20b,
# 21a, 21b, 22, 23a, 24) using ○ (asked) / X (not asked). We expand into
# one row per (variable, wave) pair, matching the project's verbatim format.

suppressPackageStartupMessages({
  library(here)
  library(readxl)
  library(dplyr)
  library(tidyr)
  library(readr)
})

codebook_path <- here("data", "kinu", "raw", "kinu_2014-2024_codebook_en.xlsx")
alias_path    <- here("data", "kinu", "questionnaire_text", "raw_to_harmonized.csv")
out_path      <- here("data", "kinu", "questionnaire_text", "kinu_verbatim_items.csv")

# Codebook column-name → wave key
WAVE_COL_MAP <- c(
  "14"  = "w2014",
  "15"  = "w2015",
  "16"  = "w2016",
  "17"  = "w2017",
  "18"  = "w2018",
  "19a" = "w2019a",
  "19b" = "w2019b",
  "20a" = "w2020a",
  "20b" = "w2020b",
  "21a" = "w2021a",
  "21b" = "w2021b",
  "22"  = "w2022",
  "23a" = "w2023",
  "24"  = "w2024"  # codebook covers 2024; data file does not — flagged
)

cb <- read_excel(codebook_path, sheet = "codebook 2014-24",
                 .name_repair = "minimal")
names(cb)[names(cb) == "Comments/\r\nleading question"] <- "Comments"

cat(sprintf("Codebook: %d variables × %d cols\n", nrow(cb), ncol(cb)))

# Drop the typo group "정치" → merge into politics
cb <- cb %>% mutate(Group = ifelse(Group == "정치", "politics", Group))

# Optional alias file
if (file.exists(alias_path)) {
  alias <- read_csv(alias_path, show_col_types = FALSE)
  cat(sprintf("Alias map: %d entries\n", nrow(alias)))
} else {
  alias <- tibble(raw_variable = character(0),
                  harmonized_name = character(0))
  cat("No alias map; harmonized_name = raw variable name\n")
}

wave_cols <- intersect(names(cb), names(WAVE_COL_MAP))
cat(sprintf("Wave columns recognised: %s\n",
            paste(wave_cols, collapse = ", ")))

# Reshape to long: one row per (variable, wave-column) pair
long <- cb %>%
  select(Group, Variable, all_of(wave_cols),
         `Item Label`, Item, Response, Comments) %>%
  pivot_longer(cols = all_of(wave_cols),
               names_to = "wave_col_raw", values_to = "presence") %>%
  mutate(wave = WAVE_COL_MAP[wave_col_raw],
         present = !is.na(presence) & presence == "○")

# Attach harmonized name (raw if no alias entry)
long <- long %>%
  left_join(alias, by = c("Variable" = "raw_variable")) %>%
  mutate(harmonized_name = ifelse(is.na(harmonized_name), Variable, harmonized_name))

# Build dictionary rows
out <- long %>%
  transmute(
    wave            = wave,
    question_id     = Variable,
    harmonized_name = harmonized_name,
    section         = Group,
    stem_text       = ifelse(present, ifelse(is.na(Comments), "", Comments), ""),
    item_text       = ifelse(present, ifelse(is.na(Item), "", Item), ""),
    response_scale  = ifelse(present, ifelse(is.na(Response), "", Response), ""),
    notes           = ifelse(present,
                             ifelse(wave == "w2024",
                                    "Codebook indicates wave 2024 fielded; not in our dataset file (kinu_2014-2023_en.sav).",
                                    ""),
                             "Not included in this wave")
  ) %>%
  arrange(harmonized_name, wave)

# Replace embedded \r\n with literal newlines (cleaner CSV)
out <- out %>%
  mutate(across(c(stem_text, item_text, response_scale, notes),
                ~ gsub("\r\n", " ", .x, fixed = TRUE)))

dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(out, out_path, na = "")

cat(sprintf("\nWrote %d rows to %s\n", nrow(out), out_path))
cat(sprintf("Distinct harmonized variables: %d\n",
            n_distinct(out$harmonized_name)))
cat(sprintf("Distinct waves: %d\n", n_distinct(out$wave)))
cat("Per-wave row counts:\n")
print(out %>% count(wave) %>% arrange(wave))
