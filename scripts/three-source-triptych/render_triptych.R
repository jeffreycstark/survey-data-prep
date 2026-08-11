# render_triptych.R — side-by-side codebook / YAML spec / raw-label cards
# for hand validation (the "manual skill"). One card per variable x wave,
# response codes aligned across the three sources with agreement marks.
#
# Usage (from repo root):
#   Rscript scripts/three-source-triptych/render_triptych.R --survey abs \
#     [--spec democracy.yml] [--var dem_country_future] [--wave w4] \
#     [--disagreements-only] [--out outputs/triptych/abs]
#
# Output: one HTML page per spec file + index.html, print-CSS'd so Cmd-P
# gives clean paper. Marks: OK = all present sources agree (normalized),
# DIFF = label text disagrees, M = code treated as missing by the spec,
# "—" = code absent in that source (neutral). A card is FLAGGED when it has
# any DIFF row, or an M row whose codebook missing_code_flag is FALSE
# (the convention-collision signature).
#
# ABS only for now. To add a survey: extend .load_codebook / .load_raw_labels /
# .SURVEYS below (see SKILL.md).

suppressMessages({
  library(here); library(yaml); library(arrow); library(dplyr)
})

# ---- args -------------------------------------------------------------------
a <- commandArgs(trailingOnly = TRUE)
getopt <- function(flag, default = NULL) {
  i <- which(a == flag)
  if (!length(i)) return(default)
  if (i == length(a) || startsWith(a[i + 1L], "--")) return(TRUE)
  a[i + 1L]
}
survey    <- getopt("--survey")
opt_spec  <- getopt("--spec")
opt_var   <- getopt("--var")
opt_wave  <- getopt("--wave")
only_flag <- isTRUE(getopt("--disagreements-only", FALSE))
out_dir   <- getopt("--out", file.path("outputs", "triptych", survey %||% "unknown"))
`%||%` <- function(x, y) if (is.null(x)) y else x

if (is.null(survey)) stop("--survey is required (currently supported: abs)")

.SURVEYS <- list(
  abs = list(
    spec_dir  = here("src", "config", "abs", "harmonize"),
    waves     = paste0("w", 1:6),
    codebook  = function() {
      f <- here("data", "abs", "codebook", paste0("w", 1:6, ".parquet"))
      bind_rows(lapply(f[file.exists(f)], read_parquet))
    },
    raw_labels = function(wave) {
      p <- here("data", "processed", paste0(wave, ".rds"))
      if (!file.exists(p)) return(NULL)
      df <- readRDS(p)
      out <- lapply(df, function(col) list(
        var_label = attr(col, "label",  exact = TRUE) %||% NA_character_,
        val_labels = attr(col, "labels", exact = TRUE)
      ))
      names(out) <- tolower(names(df))
      rm(df); gc(verbose = FALSE)
      out
    }
  )
)
if (!survey %in% names(.SURVEYS)) {
  stop(sprintf("survey '%s' not wired yet (supported: %s)",
               survey, paste(names(.SURVEYS), collapse = ", ")))
}
S <- .SURVEYS[[survey]]

# ---- load the three sources -------------------------------------------------
message("loading codebook parquet(s) ...")
cb <- S$codebook()
cb$raw_var_lc <- tolower(cb$raw_var)

message("loading raw labels from processed wave files ...")
raw_lab <- list()
for (w in S$waves) {
  message("  ", w)
  raw_lab[[w]] <- S$raw_labels(w)
}

# Check A (label reconciliation) verdicts, if the audit has been run: these
# carry the polarity semantics the dumb text comparison can't do — an "error"
# row means the declared direction contradicts the raw labels.
checkA <- local({
  f <- here("audit", "reports", survey, "04-label-reconciliation.csv")
  if (!file.exists(f)) return(NULL)
  x <- read.csv(f, stringsAsFactors = FALSE)
  x <- x[grepl("error", x$status, ignore.case = TRUE), , drop = FALSE]
  if (!nrow(x)) return(NULL)
  setNames(sprintf("%s: %s", x$status, x$message), paste(x$variable, x$wave))
})
# Check D (bin-width parity): a wave whose harmonized bins hold a different
# number of native categories than its siblings (the pole-merge / collapse
# seam class). Overlaid the same way as Check A.
checkD <- local({
  f <- here("audit", "reports", survey, "04-bin-width-parity.csv")
  if (!file.exists(f)) return(NULL)
  x <- read.csv(f, stringsAsFactors = FALSE)
  x <- x[grepl("error", x$status, ignore.case = TRUE), , drop = FALSE]
  if (!nrow(x)) return(NULL)
  setNames(sprintf("%s: %s", x$status, x$message), paste(x$variable, x$wave))
})

spec_files <- list.files(S$spec_dir, pattern = "[.]ya?ml$", full.names = TRUE)
if (!is.null(opt_spec)) {
  spec_files <- spec_files[basename(spec_files) == opt_spec]
  if (!length(spec_files)) stop("--spec did not match any file in ", S$spec_dir)
}

# ---- helpers ----------------------------------------------------------------
norm_txt <- function(x) {
  x <- tolower(trimws(as.character(x)))
  x <- gsub("[‘’′]", "'", x)
  x <- gsub("[“”]", '"', x)
  gsub("[[:space:][:punct:]]+", " ", x)
}
esc <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}
# Where does a raw code LAND under this rule? Used to render the YAML column
# for transformed waves as "-> <target code> <target label>" instead of
# misaligning the harmonized label against the raw code number (which made a
# correct reversal read as its own opposite). Unknown fns return NA -> "?".
.FN_TARGET_MAP <- list(
  recode_6pt_freq_to_4pt      = c(`1`=4, `2`=4, `3`=3, `4`=3, `5`=2, `6`=1),
  collapse_6pt_to_4pt_reverse = c(`1`=4, `2`=4, `3`=3, `4`=2, `5`=1, `6`=1),
  recode_binary_yes_no        = c(`1`=1, `2`=0)
)
map_raw_to_target <- function(rule, raw_code) {
  m <- rule$method %||% "identity"
  if (identical(m, "identity")) return(raw_code)
  if (identical(m, "recode")) {
    v <- rule$mapping[[as.character(raw_code)]]
    return(if (is.null(v)) NA_real_ else suppressWarnings(as.numeric(v)))
  }
  if (identical(m, "r_function")) {
    fn <- rule$fn %||% ""
    hit <- regmatches(fn, regexec("^safe_reverse_([0-9])pt$", fn))[[1]]
    if (length(hit) == 2) {
      n <- as.integer(hit[2])
      return(if (raw_code >= 1 && raw_code <= n) n + 1 - raw_code else NA_real_)
    }
    hit <- regmatches(fn, regexec("^safe_([0-9])pt_none$", fn))[[1]]
    if (length(hit) == 2) {
      n <- as.integer(hit[2])
      return(if (raw_code >= 1 && raw_code <= n) raw_code else NA_real_)
    }
    tm <- .FN_TARGET_MAP[[fn]]
    if (!is.null(tm)) {
      v <- tm[as.character(raw_code)]
      return(if (is.na(v)) NA_real_ else unname(v))
    }
  }
  NA_real_
}

resolve_rule <- function(var_spec, wave) {
  h <- var_spec$harmonize
  r <- h$by_wave[[wave]] %||% h$exceptions[[wave]] %||% h[[wave]] %||%
       h$default %||% list(method = "identity")
  r
}
resolve_missing <- function(var_spec, conventions) {
  codes <- numeric(0)
  key <- var_spec$missing$use_convention
  if (!is.null(key) && !is.null(conventions[[key]])) {
    cv <- conventions[[key]]
    codes <- as.numeric(if (is.list(cv) && !is.null(cv$codes)) cv$codes else cv)
  }
  codes <- unique(c(codes,
                    as.numeric(var_spec$missing$codes %||% numeric(0)),
                    as.numeric(var_spec$qc$treat_as_na %||% numeric(0))))
  list(key = key %||% "(none)", codes = codes)
}

# one card: variable x wave -> list(html=..., flagged=TRUE/FALSE) or NULL
make_card <- function(var_spec, wave, conventions, spec_file) {
  src <- var_spec$source[[wave]]
  if (is.null(src) || !nzchar(src %||% "")) return(NULL)
  src_lc <- tolower(src)

  cbk <- cb[cb$raw_var_lc == src_lc & cb$wave == wave, ]
  rl  <- raw_lab[[wave]][[src_lc]]
  yl  <- var_spec$scale$labels

  miss <- resolve_missing(var_spec, conventions)
  rule <- resolve_rule(var_spec, wave)
  is_identity <- identical(rule$method %||% "identity", "identity")
  vr   <- var_spec$qc$valid_range

  # Row universe: for identity waves the YAML target codes belong in the union
  # (they ARE the raw codes); for transformed waves they don't — a target-only
  # code would fabricate a raw-side row (e.g. harmonized 6 on a 5-category
  # wave). Raw-side sources only in that case.
  codes <- sort(unique(c(
    suppressWarnings(as.numeric(cbk$response_code)),
    if (is_identity) suppressWarnings(as.numeric(names(yl %||% list()))),
    if (!is.null(rl$val_labels)) as.numeric(rl$val_labels)
  )))
  codes <- codes[!is.na(codes)]
  if (!length(codes) && !nrow(cbk) && is.null(rl)) return(NULL)

  rows <- character(0); flagged <- FALSE; n_diff <- 0L
  for (cd in codes) {
    lab_cb  <- cbk$response_label[match(cd, suppressWarnings(as.numeric(cbk$response_code)))]
    cbflag  <- cbk$missing_code_flag[match(cd, suppressWarnings(as.numeric(cbk$response_code)))]
    lab_yml <- if (!is.null(yl)) as.character(unlist(yl[as.character(cd)]) %||% NA)[1] else NA
    lab_raw <- if (!is.null(rl$val_labels)) {
      hit <- names(rl$val_labels)[rl$val_labels == cd]
      if (length(hit)) hit[1] else NA
    } else NA

    is_miss <- cd %in% miss$codes
    # YAML scale.labels describe the HARMONIZED target scale. Under identity
    # they must match the raw wave; under recode/r_function/derive they
    # legitimately differ (that's what the transform is for), so exclude the
    # YAML column from the comparison for those waves.
    present <- if (is_identity) c(cb = lab_cb, yml = lab_yml, raw = lab_raw)
               else c(cb = lab_cb, raw = lab_raw)
    present <- present[!is.na(present) & nzchar(present)]
    # Prefix-compatible counts as agreement: YAML/codebook labels are often
    # abbreviations of the full questionnaire sentence.
    compatible <- function(a, b) {
      a <- norm_txt(a); b <- norm_txt(b)
      if (a == b) return(TRUE)
      if (nchar(a) < 4 || nchar(b) < 4) return(FALSE)
      startsWith(a, b) || startsWith(b, a)
    }
    # Hard conflict: codebook and raw describe the SAME raw item and disagree.
    # Soft divergence: the YAML wording differs from an otherwise-agreeing
    # codebook/raw pair — usually paraphrase, occasionally a direction bug;
    # shown in yellow with a '≈' mark but does not flag the card.
    hard_ok <- TRUE; soft_ok <- TRUE
    if (!is.na(lab_cb) && nzchar(lab_cb) && !is.na(lab_raw) && nzchar(lab_raw))
      hard_ok <- compatible(lab_cb, lab_raw)
    if (is_identity && "yml" %in% names(present) && length(present) >= 2L) {
      others <- present[names(present) != "yml"]
      soft_ok <- any(vapply(others, compatible, TRUE, b = present[["yml"]]))
    }
    agree <- hard_ok && soft_ok

    if (is_miss) {
      mark <- "M"; cls <- "miss"
      # collision signature: spec treats it as missing, codebook says substantive
      if (isFALSE(cbflag)) { mark <- "M!"; cls <- "collide"; flagged <- TRUE }
    } else if (!hard_ok) {
      mark <- "DIFF"; cls <- "diff"; flagged <- TRUE; n_diff <- n_diff + 1L
    } else if (!soft_ok) {
      mark <- "&asymp;"; cls <- "soft"
    } else if (length(present) >= 2L) {
      mark <- "OK"; cls <- "ok"
    } else {
      mark <- ""; cls <- "lone"
    }
    cell <- function(x) {
      x <- as.character(x %||% NA)[1]
      if (is.na(x) || !nzchar(x)) "<td class=absent>&mdash;</td>"
      else sprintf("<td>%s</td>", esc(x))
    }
    yml_cell <- if (is_identity) {
      cell(lab_yml)
    } else if (is_miss) {
      "<td class=nocompare>&mdash;</td>"
    } else {
      # Show the MAPPING, not a false 1-to-1 alignment: raw code cd lands on
      # target code tc, whose label comes from the harmonized scale.
      tc <- map_raw_to_target(rule, cd)
      if (is.na(tc)) {
        "<td class=nocompare title='mapping unknown for this fn — see method line'>&rarr; ?</td>"
      } else {
        t_lab <- if (!is.null(yl)) as.character(unlist(yl[as.character(tc)]) %||% "")[1] else ""
        sprintf("<td class=nocompare title='where this raw code lands after the transform'>&rarr; %s %s</td>",
                format(tc, trim = TRUE), esc(t_lab %||% ""))
      }
    }
    rows <- c(rows, sprintf(
      "<tr class=%s><td class=code>%s</td>%s%s%s<td class=mark>%s</td></tr>",
      cls, format(cd, trim = TRUE), cell(lab_cb), yml_cell, cell(lab_raw), mark))
  }

  ca <- NULL
  if (!is.null(checkA)) {
    hit <- checkA[paste(var_spec$id, wave)]
    if (!is.na(hit)) ca <- unname(hit)
  }
  cd4 <- NULL
  if (!is.null(checkD)) {
    hit <- checkD[paste(var_spec$id, wave)]
    if (!is.na(hit)) cd4 <- unname(hit)
  }
  if (!is.null(ca) || !is.null(cd4)) flagged <- TRUE

  # ARITY check: the raw wave's substantive code set (a contiguous run from
  # its minimum) vs the span of the harmonized target scale. Catches format
  # seams the label comparison structurally cannot see — e.g. a Yes/No wave
  # fed through a 4-pt transform, or a 5-category wave mapped by identity
  # onto a 6-category scale. Contiguity is required so endpoint-labelled
  # scales (labels only at 1 and 10) don't false-positive.
  # Exempt by-design mismatches: an explicit recode mapping already handles the
  # raw code set, and nominal items under a transform are deliberate collapses
  # (country-pick lists etc.). Ordinal seams and identity mismatches stay.
  arity <- NULL
  arity_exempt <- identical(rule$method, "recode") ||
    (identical(var_spec$type, "nominal") && !is_identity)
  raw_side <- sort(unique(c(
    suppressWarnings(as.numeric(cbk$response_code)),
    if (!is.null(rl$val_labels)) as.numeric(rl$val_labels)
  )))
  sub_codes <- if (arity_exempt) numeric(0) else
    setdiff(raw_side[!is.na(raw_side)], miss$codes)
  smin <- suppressWarnings(as.numeric(var_spec$scale$min))
  smax <- suppressWarnings(as.numeric(var_spec$scale$max))
  if (length(sub_codes) >= 2 && !is.na(smin) && !is.na(smax) &&
      all(sub_codes == floor(sub_codes)) &&
      length(sub_codes) == max(sub_codes) - min(sub_codes) + 1) {
    span <- smax - smin + 1
    if (length(sub_codes) != span) {
      arity <- sprintf(
        "raw wave carries %d substantive codes (%s) but the harmonized target scale spans %d (%s..%s) — format seam?",
        length(sub_codes), paste(range(sub_codes), collapse = ".."), span, smin, smax)
      flagged <- TRUE
    }
  }

  qtxt <- if (nrow(cbk)) esc(cbk$question_text[1]) else "<span class=absent>(no codebook entry)</span>"
  vlab <- if (!is.null(rl) && !is.na(rl$var_label)) esc(rl$var_label) else "<span class=absent>(raw variable absent)</span>"
  fn   <- rule$fn %||% ""
  html <- sprintf(
    '<div class="card%s" id="%s-%s">
<h3>%s <span class=wave>%s</span> <span class=src>&larr; %s</span>%s</h3>
<div class=meta>%s &middot; method: <b>%s</b>%s &middot; valid_range: %s &middot; missing: %s &rarr; [%s]</div>
%s<div class=qtext><b>Codebook Q:</b> %s<br><b>Raw label:</b> %s</div>
<table><tr><th>code</th><th>CODEBOOK</th><th>YAML scale.labels</th><th>RAW labels</th><th></th></tr>%s</table>
</div>',
    if (flagged) " flagged" else "", esc(var_spec$id), wave,
    esc(var_spec$id), wave, esc(src),
    if (flagged) ' <span class=flagtag>FLAGGED</span>' else "",
    esc(basename(spec_file)), esc(rule$method %||% "null"),
    if (nzchar(fn)) sprintf(" (<code>%s</code>)", esc(fn)) else "",
    if (is.null(vr)) "&mdash;" else sprintf("[%s, %s]", vr[1], vr[2]),
    esc(miss$key), paste(miss$codes, collapse = ", "),
    paste0(
      if (is.null(ca))  "" else sprintf("<div class=checka>&#9888; Check A &middot; %s</div>", esc(ca)),
      if (is.null(cd4)) "" else sprintf("<div class=checkd>&#9888; Check D &middot; %s</div>", esc(cd4)),
      if (is.null(arity)) "" else sprintf("<div class=arity>&#9888; ARITY &middot; %s</div>", esc(arity))),
    qtxt, vlab, paste(rows, collapse = "\n"))
  list(html = html, flagged = flagged)
}

CSS <- '
body{font-family:-apple-system,Helvetica,sans-serif;margin:1.2em;max-width:75em}
h1{font-size:1.3em} h3{margin:.2em 0 .1em;font-size:1.02em}
.card{border:1px solid #ccc;border-radius:6px;padding:.6em .8em;margin:.9em 0;break-inside:avoid}
.card.flagged{border-color:#c0392b;border-width:2px}
.flagtag{background:#c0392b;color:#fff;font-size:.7em;padding:1px 6px;border-radius:3px;vertical-align:middle}
.wave{color:#2471a3;font-weight:600}.src{color:#666;font-weight:400;font-size:.85em}
.meta{color:#555;font-size:.8em;margin-bottom:.3em}
.qtext{font-size:.82em;color:#333;background:#f7f7f7;padding:.3em .5em;border-radius:4px;margin-bottom:.4em}
table{border-collapse:collapse;width:100%;font-size:.82em}
th{text-align:left;border-bottom:1.5px solid #999;padding:2px 6px;font-size:.78em}
td{border-bottom:1px solid #eee;padding:2px 6px;vertical-align:top}
td.code{font-family:monospace;white-space:nowrap}
td.mark{font-family:monospace;font-weight:700;white-space:nowrap}
tr.ok td.mark{color:#1e8449} tr.diff{background:#fdecea} tr.diff td.mark{color:#c0392b}
tr.miss{color:#999} tr.miss td.mark{color:#999}
tr.soft{background:#fef9e7} tr.soft td.mark{color:#b7950b}
.checka{background:#c0392b;color:#fff;font-size:.8em;padding:.25em .5em;border-radius:4px;margin:.2em 0}
.checkd{background:#7d3c98;color:#fff;font-size:.8em;padding:.25em .5em;border-radius:4px;margin:.2em 0}
.arity{background:#b9770e;color:#fff;font-size:.8em;padding:.25em .5em;border-radius:4px;margin:.2em 0}
tr.collide{background:#fdebd0} tr.collide td.mark{color:#b9770e}
td.absent{color:#bbb} td.nocompare{color:#8a6ea0;font-style:italic}
.toc a{display:block;font-size:.9em;line-height:1.5}
@media print{.card{page-break-inside:avoid}.toc,#toolbar{display:none}body{margin:0;max-width:none}}
'

page <- function(title, body) sprintf(
  "<!doctype html><meta charset='utf-8'><title>%s</title><style>%s</style>
<h1>%s</h1><div class=meta>generated %s &middot; survey: %s%s</div>\n%s",
  esc(title), CSS, esc(title), format(Sys.time(), "%Y-%m-%d %H:%M"), survey,
  if (only_flag) " &middot; DISAGREEMENTS ONLY" else "", body)

# ---- render -----------------------------------------------------------------
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
index_rows <- character(0)
tot_cards <- 0L; tot_flag <- 0L

for (sf in spec_files) {
  sp <- tryCatch(yaml::read_yaml(sf), error = function(e) NULL)
  if (is.null(sp) || is.null(sp$variables)) next
  conventions <- sp$missing_conventions %||% list()

  cards <- list()
  for (i in seq_along(sp$variables)) {
    vs <- sp$variables[[i]]
    vid <- vs$id %||% names(sp$variables)[i]
    if (!is.null(opt_var) && !identical(vid, opt_var)) next
    vs$id <- vid
    for (w in S$waves) {
      if (!is.null(opt_wave) && !identical(w, opt_wave)) next
      cd <- make_card(vs, w, conventions, sf)
      if (!is.null(cd)) cards[[length(cards) + 1L]] <- cd
    }
  }
  if (!length(cards)) next

  n_flag <- sum(vapply(cards, `[[`, TRUE, "flagged"))
  if (only_flag) cards <- Filter(function(x) x$flagged, cards)
  if (!length(cards)) { tot_flag <- tot_flag + n_flag; next }

  fn_out <- file.path(out_dir, sub("[.]ya?ml$", ".html", basename(sf)))
  writeLines(page(
    sprintf("%s — %s", survey, basename(sf)),
    paste(vapply(cards, `[[`, "", "html"), collapse = "\n")), fn_out)
  tot_cards <- tot_cards + length(cards); tot_flag <- tot_flag + n_flag
  index_rows <- c(index_rows, sprintf(
    "<a href='%s'>%s</a> &middot; %d cards%s",
    basename(fn_out), basename(sf), length(cards),
    if (n_flag) sprintf(" &middot; <b style='color:#c0392b'>%d flagged</b>", n_flag) else ""))
}

writeLines(page(
  sprintf("Three-source triptych — %s", survey),
  sprintf("<div class=toc>%s</div><p class=meta>%d cards total, %d flagged.</p>",
          paste(index_rows, collapse = "\n"), tot_cards, tot_flag)),
  file.path(out_dir, "index.html"))

message(sprintf("done: %d cards (%d flagged) -> %s", tot_cards, tot_flag, out_dir))
