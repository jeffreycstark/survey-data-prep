#!/usr/bin/env Rscript
# Build data/kinu/questionnaire_text/raw_to_harmonized.csv from the source:
# blocks of all KINU YAMLs in src/config/kinu/harmonize/.
#
# This file feeds build_kinu_verbatim.R so the dictionary's harmonized_name
# column reflects the actual KINU harmonized variables.

suppressPackageStartupMessages({
  library(here); library(yaml); library(dplyr); library(readr)
})

yaml_dir <- here("src", "config", "kinu", "harmonize")
specs <- list.files(yaml_dir, pattern = "\\.yml$", full.names = TRUE)
cat(sprintf("Found %d YAML specs\n", length(specs)))

rows <- list()
for (f in specs) {
  spec <- read_yaml(f)
  yaml_file <- basename(f)
  for (v in spec$variables) {
    harmonized <- v$id
    src <- v$source
    raw_vars <- unique(unlist(src))
    for (rv in raw_vars) {
      rows[[length(rows) + 1]] <- data.frame(
        raw_variable    = rv,
        harmonized_name = harmonized,
        yaml_file       = yaml_file,
        stringsAsFactors = FALSE
      )
    }
  }
}

alias <- bind_rows(rows) %>% distinct() %>% arrange(yaml_file, harmonized_name, raw_variable)

out_path <- here("data", "kinu", "questionnaire_text", "raw_to_harmonized.csv")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(alias, out_path)
cat(sprintf("Wrote %s — %d rows, %d distinct harmonized vars, %d distinct raw vars\n",
            out_path, nrow(alias),
            n_distinct(alias$harmonized_name),
            n_distinct(alias$raw_variable)))
