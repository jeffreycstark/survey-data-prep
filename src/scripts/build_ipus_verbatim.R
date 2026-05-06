#!/usr/bin/env Rscript
# Build IPUS verbatim question dictionary from the SAV files' embedded
# variable labels (Korean) and value labels (Korean response options).
#
# Output: data/ipus/questionnaire_text/ipus_verbatim_items.csv
#
# Strategy: for each (harmonized_name × wave) pair in raw_to_harmonized.csv,
# pull the SAV's variable label and value labels via haven attributes.
# This works for 17 of 18 waves; 2012's SAV has labels stripped, so 2012
# rows are flagged for manual codebook extraction.

suppressPackageStartupMessages({
  library(here); library(haven); library(dplyr); library(readr)
})

source(here("src/r/data_prep_modules/ipus/0_load_waves.R"))

alias_path <- here("data/ipus/questionnaire_text/raw_to_harmonized.csv")
out_path   <- here("data/ipus/questionnaire_text/ipus_verbatim_items.csv")

alias <- read_csv(alias_path, show_col_types = FALSE)
cat(sprintf("Alias map: %d rows\n", nrow(alias)))

waves <- load_ipus_waves()

# Helper: fetch label and value-label string for a single (var, wave) pair
fetch <- function(wn, raw_var) {
  df <- waves[[wn]]
  if (!raw_var %in% names(df)) {
    return(list(item_text = NA_character_, response_scale = NA_character_,
                notes = "Variable not in this wave's SAV"))
  }
  x   <- df[[raw_var]]
  lab <- attr(x, "label")
  vl  <- attr(x, "labels")

  # Compose response scale string from value labels
  if (!is.null(vl) && length(vl) > 0) {
    scale_parts <- mapply(function(v, name) sprintf("%g=%s", v, name),
                          v = unname(vl), name = names(vl))
    response_scale <- paste(scale_parts, collapse = "; ")
  } else {
    response_scale <- NA_character_
  }

  notes <- if (is.null(lab)) "SAV has NULL variable label (likely 2012 stripped labels)" else ""

  list(
    item_text      = if (is.null(lab)) NA_character_ else lab,
    response_scale = response_scale,
    notes          = notes
  )
}

cat("Building dictionary rows...\n")
out_rows <- alias %>%
  rowwise() %>%
  mutate(
    info = list(fetch(wave, raw_variable))
  ) %>%
  mutate(
    item_text      = info$item_text,
    response_scale = info$response_scale,
    notes          = info$notes
  ) %>%
  ungroup() %>%
  select(wave, question_id = raw_variable, harmonized_name,
         section = yaml_file, item_text, response_scale, notes) %>%
  mutate(section = sub("\\.yml$", "", section))

# Add stem_text (usually NA for IPUS — questions are direct, not battery-style)
out_rows$stem_text <- ""

# Reorder to match the project's standard column order
out_rows <- out_rows %>%
  select(wave, question_id, harmonized_name, section,
         stem_text, item_text, response_scale, notes)

write_csv(out_rows, out_path, na = "")
cat(sprintf("\nWrote %d rows to %s\n", nrow(out_rows), out_path))
cat(sprintf("Distinct harmonized: %d\n", n_distinct(out_rows$harmonized_name)))
cat(sprintf("Distinct waves: %d\n", n_distinct(out_rows$wave)))
cat("Rows with NA item_text (label missing in SAV):\n")
print(out_rows %>% filter(is.na(item_text)) %>% count(wave))
