#!/usr/bin/env Rscript
# Build a merged Afrobarometer Round-10 file by stacking the per-country
# release .sav files, so R10 is available as one file like R1-R9 already are.
#
# Why this exists: Afrobarometer has not published an official merged R10
# release yet — R10 ships as per-country .sav files (same situation ABS Wave 6
# went through; cf. build_abs_w6.R). The afro loader
#   src/r/data_prep_modules/afro/0_load_waves.R
# stacks those country files on the fly, and its documented contract is: once a
# merged file exists at data/afro/raw/round10/merged_r10_data.sav, the loader
# PREFERS it and stops stacking. This script produces exactly that file, reusing
# the loader's own stacking function (.load_afro_r10_country_files) so the
# persisted file is schema-identical to the on-the-fly result — lowercased
# names, a `country_iso3` tag, haven value-labels zapped, case-variant columns
# unified. Do NOT hand-roll a different merge here: a schema mismatch (e.g.
# original-case names, or a `merge_country_code` tag instead of `country_iso3`)
# would silently change what the loader feeds downstream.
#
# Re-run whenever Afrobarometer releases another R10 country (e.g. South Africa,
# currently codebook-only): drop its .sav into data/afro/raw/round10/ and rerun.
#
# Notes:
#  * SPSS variable names cannot contain '.', so the one dotted raw name
#    `location.level.1` is written as `location_level_1` in the .sav (data
#    unchanged). It is referenced by no harmonization YAML (0 `w10:` refs).
#  * A full-fidelity .rds sibling is also written (keeps the dotted name and
#    exact string encoding); the loader consumes the .sav, the .rds is a
#    convenience copy.
#
# Outputs (both under data/afro/raw/round10/, which is gitignored):
#   merged_r10_data.sav   <- consumed by the loader (canonical)
#   merged_r10_data.rds   <- full-fidelity convenience copy

suppressPackageStartupMessages({ library(haven); library(here); library(dplyr) })

# Reuse the canonical stacking logic so this build cannot drift from what
# harmonization consumes on the fly. Sourcing this file only loads libraries and
# defines functions (no top-level execution).
source(here::here("src", "r", "data_prep_modules", "afro", "0_load_waves.R"))

round10_dir <- here::here("data", "afro", "raw", "round10")
out_sav     <- file.path(round10_dir, "merged_r10_data.sav")
out_rds     <- file.path(round10_dir, "merged_r10_data.rds")

# If a prior merged .sav is already at the path, the loader would prefer it and
# the stacker skips it (its glob only matches ^[A-Z]{3}_R10.*\.sav$), so
# regenerating is safe and idempotent.
stacked <- .load_afro_r10_country_files()
if (is.null(stacked)) stop("No R10 per-country files found under ", round10_dir)

cat(sprintf("Stacked R10: %s rows x %d cols | %d countries\n",
            format(nrow(stacked), big.mark = ","), ncol(stacked),
            dplyr::n_distinct(stacked$country_iso3)))

# Full-fidelity convenience copy first (no name/encoding constraints).
saveRDS(stacked, out_rds)
cat(sprintf("Wrote %s\n", out_rds))

# SPSS-legal names for the .sav: only characters [A-Za-z0-9_], must be unique
# case-insensitively. In practice just `location.level.1` needs the dot fixed.
to_write <- stacked
legal <- gsub("[^A-Za-z0-9_]", "_", names(to_write))
legal <- make.unique(tolower(legal), sep = "_") |>
  (\(u) { sfx <- substr(u, nchar(tolower(gsub("[^A-Za-z0-9_]","_", names(to_write)))) + 1L, nchar(u))
          paste0(gsub("[^A-Za-z0-9_]", "_", names(to_write)), sfx) })()
changed <- which(legal != names(to_write))
if (length(changed))
  cat("Renamed for SPSS legality:\n",
      paste(sprintf("   %s -> %s", names(to_write)[changed], legal[changed]), collapse = "\n"), "\n", sep = "")
names(to_write) <- legal

haven::write_sav(to_write, out_sav)
cat(sprintf("Wrote %s\n", out_sav))

# Verify the .sav re-reads to the expected shape.
chk <- haven::read_sav(out_sav, n_max = 1)
stopifnot(ncol(chk) == ncol(stacked))
cat(sprintf("Verified: merged .sav re-reads with %d columns.\n", ncol(chk)))
cat("The afro loader will now PREFER this file over on-the-fly stacking.\n")
