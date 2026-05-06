#!/usr/bin/env Rscript
# Build data/ipus/questionnaire_text/raw_to_harmonized.csv from the source:
# blocks of all IPUS YAMLs in src/config/ipus/harmonize/.

suppressPackageStartupMessages({
  library(here); library(yaml); library(dplyr); library(readr)
})

yaml_dir <- here("src", "config", "ipus", "harmonize")
specs <- list.files(yaml_dir, pattern = "\\.yml$", full.names = TRUE)
cat(sprintf("Found %d YAML specs\n", length(specs)))

rows <- list()
for (f in specs) {
  spec <- read_yaml(f)
  yaml_file <- basename(f)
  for (v in spec$variables) {
    harmonized <- v$id
    src <- v$source
    for (wn in names(src)) {
      rows[[length(rows) + 1]] <- data.frame(
        wave            = wn,
        raw_variable    = src[[wn]],
        harmonized_name = harmonized,
        yaml_file       = yaml_file,
        stringsAsFactors = FALSE
      )
    }
  }
}

alias <- bind_rows(rows) %>% distinct() %>% arrange(yaml_file, harmonized_name, wave)

out_path <- here("data", "ipus", "questionnaire_text", "raw_to_harmonized.csv")
dir.create(dirname(out_path), showWarnings = FALSE, recursive = TRUE)
write_csv(alias, out_path)
cat(sprintf("Wrote %s — %d rows, %d distinct harmonized vars, %d distinct (raw,wave) pairs\n",
            out_path, nrow(alias),
            n_distinct(alias$harmonized_name),
            nrow(alias)))
