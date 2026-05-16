#' Appendix A generator for survey-based papers
#'
#' Builds a paper-13-style "Survey Items" appendix section by pulling
#' verbatim question text from the per-survey verbatim CSVs and per-wave
#' question IDs + harmonization metadata from the harmonization YAMLs in
#' src/config/{survey}/.
#'
#' Output is markdown (ready to paste / `{{< include >}}` into a Quarto
#' manuscript). For each variable: blockquote item text, response scale,
#' harmonization note, and a per-wave QID grid. Shared-stem batteries
#' (e.g. KGSS Q35 trust battery) get the stem rendered once + numbered
#' item list.
#'
#' Usage:
#'   source("scripts/appendix-variable-builder/build_appendix.R")
#'   md <- build_appendix(
#'     survey = "abs",
#'     groups = list(
#'       "Dependent Variable: Authoritarian Openness Scale" = c(
#'         strongman_rule    = "Strong Leader",
#'         military_rule     = "Military Rule",
#'         single_party_rule = "Single-Party Rule"
#'       ),
#'       "Performance Controls" = c(
#'         democracy_satisfaction    = "Democratic Satisfaction",
#'         trust_national_government = "Trust in National Government",
#'         corrupt_national_govt     = "Corruption Perceptions",
#'         econ_national_now         = "Economic Evaluation"
#'       )
#'     )
#'   )
#'   cat(md)

suppressPackageStartupMessages({
  library(yaml)
  library(readr)
  library(dplyr)
  library(here)
})

source(here::here("scripts", "appendix-variable-builder", "recode_notes.R"))

# ---------------------------------------------------------------------------
# Source loaders
# ---------------------------------------------------------------------------

#' Load the verbatim question dictionary for a survey.
load_verbatim <- function(survey, verbatim_path = NULL) {
  if (is.null(verbatim_path)) {
    verbatim_path <- here::here(
      "data", survey, "questionnaire_text",
      paste0(survey, "_verbatim_items.csv")
    )
  }
  if (!file.exists(verbatim_path)) {
    stop("verbatim CSV not found: ", verbatim_path)
  }
  readr::read_csv(verbatim_path, show_col_types = FALSE)
}

#' Load and merge all YAML harmonization specs for a survey.
#'
#' Prefers `harmonize_validated/` when present (ABS pattern); falls back
#' to `harmonize/`.
load_specs <- function(survey, config_dir = NULL) {
  if (is.null(config_dir)) {
    validated <- here::here("src", "config", survey, "harmonize_validated")
    plain     <- here::here("src", "config", survey, "harmonize")
    config_dir <- if (dir.exists(validated)) validated else plain
  }
  if (!dir.exists(config_dir)) {
    stop("config dir not found: ", config_dir)
  }

  files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)
  out <- list()
  for (f in files) {
    spec <- yaml::read_yaml(f)
    if (is.null(spec$variables)) next
    for (v in spec$variables) {
      out[[v$id]] <- list(spec = v, file = basename(f))
    }
  }
  out
}

# ---------------------------------------------------------------------------
# Per-variable extraction
# ---------------------------------------------------------------------------

#' Extract the wave -> QID map from a YAML spec.
yaml_qid_map <- function(spec_entry) {
  src <- spec_entry$spec$source
  if (is.null(src)) return(character(0))
  src_chr <- lapply(src, function(x) if (is.null(x)) NA_character_ else as.character(x))
  vapply(src_chr, identity, character(1))
}

#' Pick the canonical wave's item_text from a verbatim slice.
#'
#' Strategy: prefer the shortest *complete-looking* item_text (ends in
#' sentence-final punctuation, after stripping trailing labels/scale text).
#' Two failure modes the heuristic guards against:
#'   1. Truncated extraction — some rows end mid-sentence (e.g. "...with the way")
#'   2. Battery concatenation — some rows have neighboring items glued on
#' Complete + shortest filters both: truncated rows are dropped (no terminal
#' punctuation), concatenated rows are demoted (longer).
canonical_item_text <- function(rows) {
  candidates <- rows$item_text[!is.na(rows$item_text) & nzchar(rows$item_text)]
  if (length(candidates) == 0) return(NA_character_)

  # Drop bilingual delimiter section (e.g. KGSS "Korean / English" — keep as-is)
  # but strip trailing whitespace.
  candidates <- trimws(candidates)

  # Complete-looking: ends in terminal punctuation
  complete <- grepl("[\\.\\?!…\"”]$", candidates, perl = TRUE)
  pool <- if (any(complete)) candidates[complete] else candidates
  pool[which.min(nchar(pool))]
}

#' Pick the canonical response_scale (first non-empty; all should be equal).
canonical_response_scale <- function(rows) {
  candidates <- rows$response_scale[!is.na(rows$response_scale) & nzchar(rows$response_scale)]
  if (length(candidates) == 0) return(NA_character_)
  candidates[1]
}

#' Pick the canonical stem_text (longest non-empty).
canonical_stem <- function(rows) {
  candidates <- rows$stem_text[!is.na(rows$stem_text) & nzchar(rows$stem_text)]
  if (length(candidates) == 0) return(NA_character_)
  candidates[which.max(nchar(candidates))]
}

#' Build the harmonization note from a YAML spec (per-wave aware).
harmonization_note <- function(spec_entry) {
  harm <- spec_entry$spec$harmonize
  if (is.null(harm)) return(NA_character_)

  default_fn <- harm$default$fn %||% harm$default$method %||% NA_character_
  exceptions <- harm$exceptions

  default_note <- if (!is.na(default_fn)) recode_note(default_fn) else NA_character_

  if (is.null(exceptions) || length(exceptions) == 0) {
    return(default_note)
  }

  # Build wave-grouped exception notes
  exc_notes <- vapply(names(exceptions), function(w) {
    fn <- exceptions[[w]]$fn %||% exceptions[[w]]$method %||% NA_character_
    note <- recode_note(fn)
    if (is.na(note)) "" else paste0(toupper(w), ": ", note)
  }, character(1))
  exc_notes <- exc_notes[nzchar(exc_notes)]

  parts <- character(0)
  if (!is.na(default_note) && nzchar(default_note)) {
    parts <- c(parts, paste0("Default: ", default_note))
  }
  parts <- c(parts, exc_notes)
  if (length(parts) == 0) return(NA_character_)
  paste(parts, collapse = " ")
}

#' Format the per-wave QID grid as a one-line string.
#'
#' Output style: "W1 q121, W2 q124, W3 q129, W4 q130, W5 q137, W6 q129."
#' Drops waves with no QID. If a wave is in the YAML source map but absent
#' from the verbatim slice (or vice versa), the value reported is taken
#' from the YAML side (the authoritative recipe).
format_qid_grid <- function(qid_map) {
  qid_map <- qid_map[!is.na(qid_map) & nzchar(qid_map) & qid_map != "NULL"]
  if (length(qid_map) == 0) return(NA_character_)
  waves <- names(qid_map)
  waves_disp <- vapply(waves, function(w) {
    # "w2003" or "y2003" -> "2003" (year-wave: don't prefix with W)
    if (grepl("^[wy](19|20)[0-9]{2}$", w)) return(sub("^[wy]", "", w))
    # "w1", "w2", ... -> "W1", "W2", ...
    if (grepl("^w[0-9]+$", w)) return(paste0("W", sub("^w", "", w)))
    # "r1", "r2" (Afrobarometer rounds) -> "R1", "R2"
    if (grepl("^r[0-9]+$", w)) return(paste0("R", sub("^r", "", w)))
    w
  }, character(1))
  paste0(paste(waves_disp, qid_map, sep = " "), collapse = ", ")
}

#' Cross-check that YAML source map and verbatim CSV agree on per-wave QIDs.
#'
#' Returns a character vector of warning messages (empty if all match).
crosscheck_qids <- function(var_id, qid_map, rows) {
  msgs <- character(0)
  cv <- rows |>
    dplyr::filter(!is.na(question_id), nzchar(question_id)) |>
    dplyr::select(wave, question_id)
  csv_map <- setNames(cv$question_id, cv$wave)

  yaml_waves <- names(qid_map)[!is.na(qid_map) & qid_map != "NULL"]
  csv_waves  <- names(csv_map)

  missing_in_csv <- setdiff(yaml_waves, csv_waves)
  if (length(missing_in_csv) > 0) {
    msgs <- c(msgs, sprintf(
      "%s: waves %s in YAML have no verbatim CSV row",
      var_id, paste(missing_in_csv, collapse = ", ")
    ))
  }
  missing_in_yaml <- setdiff(csv_waves, yaml_waves)
  if (length(missing_in_yaml) > 0) {
    msgs <- c(msgs, sprintf(
      "%s: waves %s in verbatim CSV have no YAML source mapping",
      var_id, paste(missing_in_yaml, collapse = ", ")
    ))
  }
  overlap <- intersect(yaml_waves, csv_waves)
  for (w in overlap) {
    if (!identical(as.character(qid_map[[w]]), as.character(csv_map[[w]]))) {
      msgs <- c(msgs, sprintf(
        "%s wave %s: YAML says %s, verbatim CSV says %s",
        var_id, w, qid_map[[w]], csv_map[[w]]
      ))
    }
  }
  msgs
}

# ---------------------------------------------------------------------------
# Markdown rendering
# ---------------------------------------------------------------------------

#' Render a single variable as markdown (paper-13 style).
render_variable <- function(var_id, display_name, verbatim, specs,
                            warnings_env = NULL) {
  rows <- verbatim |> dplyr::filter(harmonized_name == var_id)
  if (nrow(rows) == 0) {
    return(sprintf(
      "### %s (`%s`)\n\n*[No verbatim CSV rows found for `%s`.]*\n",
      display_name, var_id, var_id
    ))
  }

  spec_entry <- specs[[var_id]]
  qid_map <- if (!is.null(spec_entry)) yaml_qid_map(spec_entry) else character(0)

  if (!is.null(spec_entry) && !is.null(warnings_env)) {
    msgs <- crosscheck_qids(var_id, qid_map, rows)
    if (length(msgs) > 0) {
      warnings_env$msgs <- c(warnings_env$msgs, msgs)
    }
  }

  item_text     <- canonical_item_text(rows)
  # Defensive fallback: if verbatim CSV item_text is suspiciously short
  # (likely a PDF-extraction truncation that escaped patching), substitute
  # the YAML description with a paraphrase marker.
  if (!is.na(item_text) && nchar(item_text) < 15 &&
      !is.null(spec_entry) && !is.null(spec_entry$spec$description)) {
    item_text <- paste0(spec_entry$spec$description, " *[paraphrased; verbatim CSV row appears truncated]*")
    if (!is.null(warnings_env)) {
      warnings_env$msgs <- c(warnings_env$msgs, sprintf(
        "%s: verbatim CSV item_text < 15 chars; fell back to YAML description.",
        var_id
      ))
    }
  }
  response_text <- canonical_response_scale(rows)
  harm_note     <- if (!is.null(spec_entry)) harmonization_note(spec_entry) else NA_character_
  qid_grid      <- format_qid_grid(qid_map)

  parts <- c(sprintf("### %s (`%s`)\n", display_name, var_id))

  if (!is.na(item_text)) {
    parts <- c(parts, sprintf("> *\"%s\"*\n", item_text))
  } else {
    parts <- c(parts, "*[Item text not found in verbatim dictionary.]*\n")
  }

  if (!is.na(response_text)) {
    parts <- c(parts, sprintf("**Response scale:** %s\n", response_text))
  }

  if (!is.na(harm_note) && nzchar(harm_note)) {
    parts <- c(parts, sprintf("**Harmonization:** %s\n", harm_note))
  }

  if (!is.na(qid_grid)) {
    parts <- c(parts, sprintf("**Wave QIDs:** %s.\n", qid_grid))
  }

  paste(parts, collapse = "\n")
}

#' Detect whether a group of variables shares a stem (battery pattern).
shared_stem <- function(var_ids, verbatim) {
  stems <- vapply(var_ids, function(v) {
    rows <- verbatim |> dplyr::filter(harmonized_name == v)
    if (nrow(rows) == 0) return(NA_character_)
    canonical_stem(rows) %||% NA_character_
  }, character(1))
  stems <- stems[!is.na(stems) & nzchar(stems)]
  if (length(stems) < 2) return(NA_character_)
  if (length(unique(stems)) == 1) return(stems[1])
  NA_character_
}

#' Render a group of variables as a battery (shared stem) if applicable.
render_battery <- function(group_name, items, verbatim, specs, warnings_env) {
  var_ids <- names(items)
  shared <- shared_stem(var_ids, verbatim)
  if (is.na(shared)) return(NULL)

  # Detect shared response scale too
  scales <- vapply(var_ids, function(v) {
    rows <- verbatim |> dplyr::filter(harmonized_name == v)
    if (nrow(rows) == 0) return(NA_character_)
    canonical_response_scale(rows) %||% NA_character_
  }, character(1))
  scales <- scales[!is.na(scales) & nzchar(scales)]
  shared_scale <- if (length(unique(scales)) == 1) scales[1] else NA_character_

  parts <- c(sprintf("## %s\n", group_name))
  parts <- c(parts, sprintf("**Battery stem:** %s\n", shared))
  if (!is.na(shared_scale)) {
    parts <- c(parts, sprintf("**Response scale (all items):** %s\n", shared_scale))
  }

  for (v in var_ids) {
    rows <- verbatim |> dplyr::filter(harmonized_name == v)
    spec_entry <- specs[[v]]
    qid_map <- if (!is.null(spec_entry)) yaml_qid_map(spec_entry) else character(0)

    if (!is.null(spec_entry) && !is.null(warnings_env)) {
      msgs <- crosscheck_qids(v, qid_map, rows)
      if (length(msgs) > 0) warnings_env$msgs <- c(warnings_env$msgs, msgs)
    }

    item_text <- canonical_item_text(rows)
    qid_grid  <- format_qid_grid(qid_map)
    harm_note <- if (!is.null(spec_entry)) harmonization_note(spec_entry) else NA_character_

    parts <- c(parts, sprintf("### %s (`%s`)\n", items[[v]], v))
    if (!is.na(item_text)) parts <- c(parts, sprintf("> *\"%s\"*\n", item_text))
    if (is.na(shared_scale) && !is.na(canonical_response_scale(rows))) {
      parts <- c(parts, sprintf("**Response scale:** %s\n", canonical_response_scale(rows)))
    }
    if (!is.na(harm_note) && nzchar(harm_note)) {
      parts <- c(parts, sprintf("**Harmonization:** %s\n", harm_note))
    }
    if (!is.na(qid_grid)) {
      parts <- c(parts, sprintf("**Wave QIDs:** %s.\n", qid_grid))
    }
  }
  paste(parts, collapse = "\n")
}

#' Render a non-battery group as a list of individual variables.
render_group <- function(group_name, items, verbatim, specs, warnings_env) {
  parts <- c(sprintf("## %s\n", group_name))
  for (v in names(items)) {
    parts <- c(parts, render_variable(v, items[[v]], verbatim, specs, warnings_env))
  }
  paste(parts, collapse = "\n")
}

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

#' Build an Appendix A markdown section from a per-survey verbatim CSV +
#' YAML harmonization specs.
#'
#' @param survey  Character: "abs", "wvs", "kgss", "afro", "lbs", ...
#' @param groups  Named list. Each element name is a section heading; each
#'                value is a named character vector mapping
#'                `harmonized_name = "Display Name"`. When all items in a
#'                group share an identical stem, the group is auto-rendered
#'                as a battery (stem once + items below).
#' @param title   Top-level heading (default "Appendix A: Survey Items").
#' @param intro   Optional intro paragraph after the title.
#' @param force_battery Optional character vector of group names to force
#'                      battery rendering even if stems differ slightly.
#' @param verbatim_path Override path to verbatim CSV.
#' @param config_dir    Override path to YAML config dir.
#' @param output_file   Optional path to write markdown.
#'
#' @return Character: the rendered markdown. Also prints any QID cross-check
#'         warnings to stderr.
build_appendix <- function(survey,
                           groups,
                           title = "Appendix A: Survey Items",
                           intro = NULL,
                           force_battery = character(0),
                           verbatim_path = NULL,
                           config_dir = NULL,
                           output_file = NULL) {

  verbatim <- load_verbatim(survey, verbatim_path)
  specs    <- load_specs(survey, config_dir)

  warnings_env <- new.env()
  warnings_env$msgs <- character(0)

  parts <- c(sprintf("# %s\n", title))
  if (!is.null(intro)) parts <- c(parts, paste0(intro, "\n"))

  for (group_name in names(groups)) {
    items <- groups[[group_name]]
    rendered <- NULL
    if (group_name %in% force_battery || length(items) >= 2) {
      rendered <- render_battery(group_name, items, verbatim, specs, warnings_env)
    }
    if (is.null(rendered)) {
      rendered <- render_group(group_name, items, verbatim, specs, warnings_env)
    }
    parts <- c(parts, rendered, "---\n")
  }

  md <- paste(parts, collapse = "\n")

  if (length(warnings_env$msgs) > 0) {
    message("Cross-check warnings (", length(warnings_env$msgs), "):")
    for (m in warnings_env$msgs) message("  - ", m)
  }

  if (!is.null(output_file)) {
    writeLines(md, output_file)
    message("Wrote ", output_file)
  }
  invisible(md)
}

# Internal: %||% (fall back if NULL)
`%||%` <- function(a, b) if (is.null(a)) b else a
