library(here)
library(dplyr)
library(tidyr)
library(readr)

out_dir <- here("data", "processed")

clean_q <- function(x) {
  x <- trimws(x)
  x <- gsub("SHOWCARD[^.]*\\.?", "", x, ignore.case = TRUE)
  x <- gsub("SHOW CARD[^.]*\\.?", "", x, ignore.case = TRUE)
  x <- gsub("\u3010[^\u3011]*\u3011", "", x)
  x <- gsub("^[A-Z]?Q?[0-9]+[-.]\\s*", "", x)
  x <- gsub("\\s{2,}", " ", x)
  trimws(x)
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. ABS
# ─────────────────────────────────────────────────────────────────────────────
cat("Building ABS...\n")
cb <- read_csv(here("data", "processed", "abs_variable_codebook.csv"),
               show_col_types = FALSE)

src_cols     <- paste0("w", 1:6, "_source")
wording_cols <- paste0("w", 1:6, "_wording")
src_mat     <- as.matrix(cb[, src_cols])
wording_mat <- as.matrix(cb[, wording_cols])

abs_display <- cb %>%
  mutate(
    waves = apply(src_mat, 1, function(row) {
      # NA or empty = absent
      present <- !is.na(row) & nchar(trimws(row)) > 0
      paste(paste0("W", 1:6)[present], collapse = ", ")
    }),
    question_text = trimws(description),
    response_scale = gsub(";", ",", scale_labels),
    wording_note = apply(wording_mat, 1, function(row) {
      wds <- row[!is.na(row)]
      wds <- trimws(wds)
      wds <- wds[nchar(wds) > 0]
      wds_clean <- trimws(gsub("\\[.*$", "", wds))
      wds_clean <- wds_clean[nchar(wds_clean) > 0]
      if (length(unique(wds_clean)) > 1) "Question wording varied across waves" else ""
    })
  ) %>%
  filter(nchar(waves) > 0) %>%
  select(harmonized_name, question_text, response_scale, waves, wording_note)

write_csv(abs_display, file.path(out_dir, "abs_codebook_display.csv"))
cat(sprintf("  ABS: %d variables\n", nrow(abs_display)))

# ─────────────────────────────────────────────────────────────────────────────
# HELPER: collapse long-format verbatim CSV
# ─────────────────────────────────────────────────────────────────────────────
collapse_verbatim <- function(df) {
  df <- df %>%
    mutate(
      item_text  = coalesce(item_text, ""),
      stem_text  = coalesce(stem_text, ""),
      notes      = coalesce(notes, ""),
      response_scale = coalesce(response_scale, ""),
      present = !grepl("Not included", notes, ignore.case = TRUE) &
                (nchar(trimws(item_text)) > 0 | nchar(trimws(stem_text)) > 0)
    )

  present_df <- df %>% filter(present)
  if (nrow(present_df) == 0) return(tibble(harmonized_name = character()))

  wave_order <- sort(unique(df$wave))
  present_df <- present_df %>%
    mutate(wave_f = factor(wave, levels = wave_order)) %>%
    arrange(harmonized_name, wave_f)

  present_df %>%
    group_by(harmonized_name) %>%
    summarise(
      waves_raw = paste(as.character(wave[order(wave_f)]), collapse = "|"),

      question_text = {
        n   <- n()
        stm <- trimws(stem_text[n])
        itm <- clean_q(trimws(item_text[n]))
        if (nchar(stm) > 5 && nchar(stm) < 200 &&
            grepl("\\?", stm) &&
            !grepl("(Strongly|Very|Quite|None|Not at all|Don't know)", stm)) {
          paste0(clean_q(stm), " [", itm, "]")
        } else {
          itm
        }
      },

      response_scale = {
        rs <- trimws(response_scale)
        rs <- rs[nchar(rs) > 0]
        if (length(rs) > 0) tail(rs, 1) else ""
      },

      wording_note = {
        texts <- clean_q(trimws(item_text))
        texts <- texts[nchar(texts) > 0]
        if (length(unique(texts)) > 1) "Question wording varied across waves" else ""
      },

      .groups = "drop"
    ) %>%
    mutate(waves = waves_raw) %>%
    select(harmonized_name, question_text, response_scale, waves, wording_note)
}

# ─────────────────────────────────────────────────────────────────────────────
# 2-5. Other surveys
# ─────────────────────────────────────────────────────────────────────────────
surveys <- list(
  list(
    name = "Afrobarometer",
    path = here("data", "afro", "questionnaire_text", "afro_verbatim_items.csv"),
    out  = "afro_codebook_display.csv",
    wave_fmt = function(w) gsub("\\|", ", ", gsub("w([0-9]+)", "R\\1", w))
  ),
  list(
    name = "Arab Barometer",
    path = here("data", "arab-barometer", "questionnaire_text", "arab_barometer_verbatim_items.csv"),
    out  = "arab_barometer_codebook_display.csv",
    wave_fmt = function(w) gsub("\\|", ", ", gsub("w([0-9]+)", "W\\1", w))
  ),
  list(
    name = "KAMOS",
    path = here("data", "kamos", "questionnaire_text", "kamos_verbatim_items.csv"),
    out  = "kamos_codebook_display.csv",
    wave_fmt = function(w) gsub("\\|", ", ", gsub("w([0-9]+)", "W\\1", w))
  ),
  list(
    name = "KIPA/KSIS",
    path = here("data", "kipa", "questionnaire_text", "kipa_verbatim_items.csv"),
    out  = "ksis_codebook_display.csv",
    wave_fmt = function(w) gsub("\\|", ", ", gsub("y([0-9]+)", "\\1", w))
  )
)

for (s in surveys) {
  cat(sprintf("Building %s...\n", s$name))
  raw <- read_csv(s$path, show_col_types = FALSE)
  disp <- collapse_verbatim(raw) %>%
    mutate(waves = sapply(waves, s$wave_fmt)) %>%
    select(harmonized_name, question_text, response_scale, waves, wording_note)
  write_csv(disp, file.path(out_dir, s$out))
  cat(sprintf("  %s: %d variables\n", s$name, nrow(disp)))
}

cat("\n✅ Done.\n")
