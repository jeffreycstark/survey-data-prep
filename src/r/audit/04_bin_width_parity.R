#!/usr/bin/env Rscript
# src/r/audit/04_bin_width_parity.R
#
# Layer 4 — Check D: bin-width parity across waves.
#
# Motivating bug: ABS W5 fielded the institutional-trust battery on a
# 6-point bipolar scale; safe_6pt_to_4pt collapses to the 4-point target by
# merging BOTH poles (native 6,5 -> 4; 2,1 -> 1). W5's top bin therefore
# absorbs two native categories while every other wave's absorbs one —
# top-box shares inflate ~2.4-4.6x in all 13 trust items, in every country
# (confirmed 2026-07-21; see docs/superpowers/specs/
# 2026-07-22-bin-width-parity-check-design.md). Direction-based layers
# (label recon, strict reversal, battery coherence) pass this legitimately:
# the mapping is directionally correct. This check tests the SHAPE of the
# mapping instead — the number of source categories feeding each target bin
# must be constant across waves, or the variable's levels are not
# cross-wave comparable.
#
# STATIC evaluation only: signatures come from YAML recode mappings and
# from calling registry-declared data-independent fns over their declared
# input domain (the engine passes no substantive extra args — see
# harmonize.R r_function dispatch — so defaults mirror production).
# An empirical raw->harmonized crosstab arm (would catch raw domains wider
# than the registry declares) is DEFERRED: it needs per-survey raw loaders,
# which exist only for ABS today (04_strict_reversal.R .SURVEY_RAW_LOADERS).
#
# Statuses:
#   ok                — signature agrees with the variable's modal signature
#                       (or nothing to compare / uniform collapse everywhere)
#   ok_exempt         — variable listed in bin_width_exemptions.yml
#   parity_error      — signature deviates from modal AND a width >= 2 bin is
#                       involved (the ABS-W5 class; audit finding)
#   warn              — signatures differ but all widths are 1 (cardinality/
#                       domain drift, not a width artefact)
#   no_registry_entry — r_function fn absent from recoding_registry.yml
#   skip              — statically unevaluable (derive, requires_data fn,
#                       null source, no numeric scale, fn errored on domain)
#
# Public API:
#   compute_bin_width_parity(survey, ...)  -- returns a data.frame
#   run_bin_width_parity(survey, ...)      -- writes CSV + prints summary
# CLI:
#   Rscript src/r/audit/04_bin_width_parity.R --survey abs
#   Rscript src/r/audit/04_bin_width_parity.R --all-surveys
# Exit: 0 if no parity_error rows, 1 otherwise (hard check).

suppressPackageStartupMessages({
  library(yaml)
  library(here)
})

source(here::here("src", "r", "utils", "spec_discovery.R"))
source(here::here("src", "r", "utils", "recoding.R"))

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---------------------------------------------------------------------------
# Mirror of harmonize.R::resolve_wave_rule(). Same inline-mirror convention
# as 04_strict_reversal.R — if engine resolution semantics change, update
# both; they MUST agree.
# ---------------------------------------------------------------------------
.resolve_wave_rule <- function(var_spec, wave_name) {
  default_rule <- var_spec$harmonize$default %||% list(method = "identity")
  var_spec$harmonize$by_wave[[wave_name]] %||%
    var_spec$harmonize$exceptions[[wave_name]] %||%
    var_spec$harmonize[[wave_name]] %||%
    default_rule
}

# ---------------------------------------------------------------------------
# Signature helpers. A signature is a named integer vector: names = target
# values, values = how many source categories map there. Serialized with
# targets sorted DESCENDING: ABS W5 trust = "4:2|3:1|2:1|1:2".
# ---------------------------------------------------------------------------
.sig_string <- function(widths) {
  t_num <- as.numeric(names(widths))
  ord <- order(-t_num)
  paste(sprintf("%s:%d", names(widths)[ord], as.integer(widths[ord])),
        collapse = "|")
}

.sig_result <- function(status, method, fn, message = "",
                        widths = NULL) {
  list(
    status = status,
    signature = if (is.null(widths)) NA_character_ else .sig_string(widths),
    n_bins = if (is.null(widths)) NA_integer_ else length(widths),
    max_width = if (is.null(widths)) NA_integer_ else max(as.integer(widths)),
    fn = fn %||% NA_character_,
    method = method,
    message = message
  )
}

# ---------------------------------------------------------------------------
# bin_signature(): derive one wave's signature from its resolved rule.
#   rule     — list from .resolve_wave_rule()
#   scale    — var_spec$scale (list with min/max), may be NULL
#   registry — named list: fn name -> registry entry
# ---------------------------------------------------------------------------
bin_signature <- function(rule, scale, registry) {
  method <- rule$method %||% "identity"

  if (method == "identity") {
    lo <- suppressWarnings(as.numeric(scale$min %||% NA))
    hi <- suppressWarnings(as.numeric(scale$max %||% NA))
    if (is.na(lo) || is.na(hi) || hi < lo) {
      return(.sig_result("skip", method, NA_character_,
                         "identity without numeric scale min/max"))
    }
    targets <- seq(lo, hi)
    widths <- stats::setNames(rep(1L, length(targets)), targets)
    return(.sig_result("pending", method, NA_character_, widths = widths))
  }

  if (method == "recode") {
    mapping <- rule$mapping
    if (is.null(mapping) || length(mapping) == 0) {
      return(.sig_result("skip", method, NA_character_,
                         "recode without mapping"))
    }
    to <- vapply(mapping, function(v) {
      if (is.null(v)) NA_real_ else suppressWarnings(as.numeric(v))
    }, numeric(1))
    to <- to[!is.na(to)]  # null-mapped (-> NA) inputs are not a bin
    if (length(to) == 0) {
      return(.sig_result("skip", method, NA_character_,
                         "recode maps every input to NA"))
    }
    tab <- table(to)
    widths <- stats::setNames(as.integer(tab), names(tab))
    return(.sig_result("pending", method, NA_character_, widths = widths))
  }

  if (method == "r_function") {
    fn_name <- rule$fn %||% NA_character_
    entry <- registry[[fn_name]]
    if (is.null(entry)) {
      return(.sig_result("no_registry_entry", method, fn_name,
                         sprintf("fn '%s' not in recoding_registry.yml",
                                 fn_name)))
    }
    if (isTRUE(entry$requires_data)) {
      return(.sig_result("skip", method, fn_name,
                         "requires_data fn — not statically evaluable"))
    }
    isc <- suppressWarnings(as.numeric(unlist(entry$input_scale)))
    if (length(isc) != 2 || any(is.na(isc))) {
      return(.sig_result("skip", method, fn_name,
                         "no numeric input_scale in registry"))
    }
    if (!exists(fn_name, mode = "function")) {
      return(.sig_result("skip", method, fn_name,
                         sprintf("fn '%s' not loaded from recoding.R",
                                 fn_name)))
    }
    f <- get(fn_name, mode = "function")
    domain <- seq(isc[1], isc[2])
    out <- tryCatch(
      suppressWarnings(as.numeric(f(domain))),
      error = function(e) e
    )
    if (inherits(out, "error")) {
      return(.sig_result("skip", method, fn_name,
                         sprintf("fn errored on declared domain %s..%s: %s",
                                 isc[1], isc[2], conditionMessage(out))))
    }
    keep <- !is.na(out)  # domain values the fn sends to NA are not a bin
    if (!any(keep)) {
      return(.sig_result("skip", method, fn_name,
                         "fn maps entire declared domain to NA"))
    }
    tab <- table(out[keep])
    widths <- stats::setNames(as.integer(tab), names(tab))
    return(.sig_result("pending", method, fn_name, widths = widths))
  }

  .sig_result("skip", method, rule$fn %||% NA_character_,
              sprintf("method '%s' out of scope for static bin analysis",
                      method))
}

# ---------------------------------------------------------------------------
# Parity judgment over one variable's computed rows.
#   Uniform signatures (or <2 usable waves) -> ok.
#   Deviant waves -> parity_error when any usable wave has max_width >= 2,
#   else warn (all-1:1 domain/cardinality drift).
# ---------------------------------------------------------------------------
.judge_parity <- function(df) {
  pending <- df$status == "pending"
  if (!any(pending)) return(df)
  sigs <- df$signature[pending]
  if (length(unique(sigs)) <= 1L) {
    df$status[pending] <- "ok"
    return(df)
  }
  tab <- table(sigs)
  cands <- names(tab)[tab == max(tab)]
  if (length(cands) > 1L) {
    # Tie-break: the baseline is the least-collapsed signature — all-width-1
    # before width>=2, then the wider domain, then alphabetical. The
    # collapsing/narrowed wave is the artefact, not the 1:1 wave.
    meta <- lapply(cands, function(s) {
      i <- which(pending & df$signature == s)[1]
      list(sig = s, mw = df$max_width[i], nb = df$n_bins[i])
    })
    ord <- order(
      vapply(meta, function(m) as.integer(m$mw > 1L), integer(1)),
      -vapply(meta, function(m) as.integer(m$nb), integer(1)),
      vapply(meta, function(m) m$sig, character(1))
    )
    modal <- meta[[ord[1]]]$sig
  } else {
    modal <- cands
  }
  any_wide <- any(df$max_width[pending] >= 2L, na.rm = TRUE)
  deviant_status <- if (any_wide) "parity_error" else "warn"
  is_deviant <- pending & df$signature != modal
  df$status[pending & df$signature == modal] <- "ok"
  df$status[is_deviant] <- deviant_status
  df$message[is_deviant] <- sprintf(
    "signature %s deviates from modal %s", df$signature[is_deviant], modal)
  df
}

# ---------------------------------------------------------------------------
# compute_bin_width_for_var(): all waves of one variable -> judged rows.
#   exempt_ids — character vector of exempted variable ids for this survey.
# ---------------------------------------------------------------------------
compute_bin_width_for_var <- function(var_spec, survey, registry,
                                      exempt_ids = character(0)) {
  var_id <- var_spec$id %||% "?"
  waves <- names(var_spec$source %||% list())
  rows <- lapply(waves, function(wv) {
    src <- var_spec$source[[wv]]
    if (is.null(src)) {
      sig <- .sig_result("skip", "none", NA_character_,
                         "null source for this wave")
    } else {
      rule <- .resolve_wave_rule(var_spec, wv)
      sig <- bin_signature(rule, var_spec$scale, registry)
    }
    data.frame(
      survey = survey, variable = var_id, wave = wv,
      method = sig$method, fn = sig$fn, signature = sig$signature,
      n_bins = sig$n_bins, max_width = sig$max_width,
      status = sig$status, message = sig$message,
      stringsAsFactors = FALSE
    )
  })
  df <- do.call(rbind, rows)
  if (is.null(df)) {
    return(data.frame(
      survey = character(0), variable = character(0), wave = character(0),
      method = character(0), fn = character(0), signature = character(0),
      n_bins = integer(0), max_width = integer(0), status = character(0),
      message = character(0), stringsAsFactors = FALSE
    ))
  }
  df <- .judge_parity(df)
  if (var_id %in% exempt_ids) {
    computed <- df$status %in% c("ok", "parity_error", "warn")
    df$message[computed] <- paste0(
      "exempt (bin_width_exemptions.yml); computed status was ",
      df$status[computed])
    df$status[computed] <- "ok_exempt"
  }
  df
}

# ---------------------------------------------------------------------------
# Registry + exemptions loaders.
# ---------------------------------------------------------------------------
load_bin_width_registry <- function(
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml")
) {
  if (!file.exists(registry_path)) {
    stop(sprintf("recoding registry not found at %s", registry_path),
         call. = FALSE)
  }
  reg <- yaml::read_yaml(registry_path)
  stats::setNames(reg, vapply(reg, function(e) e$fn, character(1)))
}

load_bin_width_exemptions <- function(
  survey,
  exemptions_path = here::here("src", "config", "_audit",
                               "bin_width_exemptions.yml")
) {
  if (!file.exists(exemptions_path)) return(character(0))
  ex <- yaml::read_yaml(exemptions_path)
  entries <- ex$exempt_variables %||% list()
  ids <- vapply(entries, function(e) {
    if (!is.null(e$survey) && !identical(e$survey, survey)) NA_character_
    else e$variable %||% NA_character_
  }, character(1))
  ids[!is.na(ids)]
}

# ---------------------------------------------------------------------------
# compute_bin_width_parity(): whole survey -> judged rows.
# ---------------------------------------------------------------------------
compute_bin_width_parity <- function(
  survey,
  registry_path = here::here("src", "r", "utils", "recoding_registry.yml"),
  exemptions_path = here::here("src", "config", "_audit",
                               "bin_width_exemptions.yml")
) {
  registry <- load_bin_width_registry(registry_path)
  exempt_ids <- load_bin_width_exemptions(survey, exemptions_path)
  spec_files <- list_survey_specs(survey)
  out <- list()
  for (sf in spec_files) {
    spec <- tryCatch(yaml::read_yaml(sf), error = function(e) NULL)
    if (is.null(spec) || is.null(spec$variables)) next
    for (vs in spec$variables) {
      out[[length(out) + 1L]] <-
        compute_bin_width_for_var(vs, survey, registry, exempt_ids)
    }
  }
  if (length(out) == 0L) {
    return(data.frame(
      survey = character(0), variable = character(0), wave = character(0),
      method = character(0), fn = character(0), signature = character(0),
      n_bins = integer(0), max_width = integer(0), status = character(0),
      message = character(0), stringsAsFactors = FALSE
    ))
  }
  do.call(rbind, out)
}

# ---------------------------------------------------------------------------
# run_bin_width_parity(): CSV + human summary. Returns df invisibly.
# ---------------------------------------------------------------------------
run_bin_width_parity <- function(survey, output_dir = NULL) {
  if (is.null(output_dir)) {
    output_dir <- here::here("audit", "reports", survey)
  }
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }
  results <- compute_bin_width_parity(survey)
  csv_path <- file.path(output_dir, "04-bin-width-parity.csv")
  utils::write.csv(results, csv_path, row.names = FALSE)

  n <- function(s) sum(results$status == s)
  cat(sprintf("\n[bin-width parity] survey=%s\n", survey))
  cat(sprintf(
    "  rows=%d: ok=%d, ok_exempt=%d, parity_error=%d, warn=%d, no_registry_entry=%d, skip=%d\n",
    nrow(results), n("ok"), n("ok_exempt"), n("parity_error"), n("warn"),
    n("no_registry_entry"), n("skip")))
  err <- results[results$status == "parity_error", , drop = FALSE]
  if (nrow(err) > 0L) {
    cat(sprintf("  %d parity_error row(s) — waves whose binning diverges:\n",
                nrow(err)))
    show <- utils::head(err, 20L)
    for (i in seq_len(nrow(show))) {
      cat(sprintf("    %-32s %-6s %s (%s)\n", show$variable[i],
                  show$wave[i], show$signature[i], show$fn[i]))
    }
    if (nrow(err) > 20L) cat(sprintf("    ... and %d more\n", nrow(err) - 20L))
  }
  cat(sprintf("  CSV: %s\n", csv_path))
  invisible(results)
}

# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------
.parse_cli_args <- function(argv) {
  out <- list(survey = NULL, all_surveys = FALSE)
  i <- 1L
  while (i <= length(argv)) {
    a <- argv[i]
    if (a == "--survey")      { out$survey <- argv[i + 1]; i <- i + 2; next }
    if (a == "--all-surveys") { out$all_surveys <- TRUE;   i <- i + 1; next }
    if (a %in% c("-h", "--help")) {
      cat("Usage: Rscript src/r/audit/04_bin_width_parity.R\n",
          "         (--survey <name> | --all-surveys)\n",
          "\nCheck D: cross-wave bin-width parity. parity_error = a wave's\n",
          "recode packs more source categories into a target bin than its\n",
          "sibling waves (ABS W5 6->4 trust class). Exemptions:\n",
          "src/config/_audit/bin_width_exemptions.yml. Exit 1 on any\n",
          "parity_error.\n", sep = "")
      quit(status = 0)
    }
    stop(sprintf("unknown argument: %s", a), call. = FALSE)
  }
  if (is.null(out$survey) && !out$all_surveys) {
    stop("usage: --survey <name> OR --all-surveys (see --help)", call. = FALSE)
  }
  out
}

if (sys.nframe() == 0L) {
  argv <- commandArgs(trailingOnly = TRUE)
  if (length(argv) > 0) {
    args <- .parse_cli_args(argv)
    surveys <- if (args$all_surveys) {
      dirs <- list.dirs(here::here("src", "config"), recursive = FALSE,
                        full.names = FALSE)
      dirs[!startsWith(dirs, "_")]  # _anchors, _audit, _schema, ...
    } else args$survey
    any_err <- FALSE
    for (s in surveys) {
      res <- tryCatch(run_bin_width_parity(s), error = function(e) {
        cat(sprintf("[bin-width parity] %s CRASHED: %s\n",
                    s, conditionMessage(e)))
        NULL
      })
      if (!is.null(res) && any(res$status == "parity_error")) any_err <- TRUE
    }
    quit(status = if (any_err) 1L else 0L)
  }
}
