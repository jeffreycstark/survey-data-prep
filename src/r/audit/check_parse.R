#!/usr/bin/env Rscript
# src/r/audit/check_parse.R
#
# Fast syntax gate: parse every R file under src/r and report the ones that
# fail. Catches a broken edit before any of the heavier audit layers spend
# time loading data.
#
# This lives in a script rather than inline in the Makefile deliberately.
# A recipe carrying multi-line R inside single quotes relies on the shell
# treating backslash-newline as a continuation, which it does not do inside
# quotes — that passed on macOS and failed on the Ubuntu CI runner with
# "unexpected end of line".
#
# CLI:
#   Rscript src/r/audit/check_parse.R [dir]     # default dir: src/r
#
# Exit codes:
#   0  every file parsed
#   1  at least one file failed to parse

args <- commandArgs(trailingOnly = TRUE)
# Default to BOTH R trees. `scripts/` sat outside the gate, which is how
# scripts/combine_harmonized_datasets.R shipped with `if (wave in names(...))`
# — Python syntax that has never parsed — without anything noticing.
roots <- if (length(args) >= 1L) args else c("src/r", "scripts")
roots <- roots[dir.exists(roots)]

if (length(roots) == 0L) {
  cat("check_parse: no such directory\n")
  quit(status = 1L)
}

files <- unlist(lapply(roots, list.files, pattern = "[.][Rr]$",
                       recursive = TRUE, full.names = TRUE))

bad <- character(0)
for (f in files) {
  ok <- tryCatch({
    parse(f)
    TRUE
  }, error = function(e) {
    cat(sprintf("PARSE FAIL: %s - %s\n", f, conditionMessage(e)))
    FALSE
  })
  if (!ok) bad <- c(bad, f)
}

cat(sprintf("parsed %d R files under %s, %d failures\n",
            length(files), paste(roots, collapse = " + "), length(bad)))

quit(status = if (length(bad)) 1L else 0L)
