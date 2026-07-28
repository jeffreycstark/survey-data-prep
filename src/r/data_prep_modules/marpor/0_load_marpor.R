# MARPOR / CMP: Load raw Manifesto Project Main Dataset
#
# Manifesto Project (MARPOR/CMP) Main Dataset — party × election panel.
# Unit of observation: party × election (NOT individual respondents).
#
# ⚠️ THIS IS NOT A SURVEY. There is no questionnaire and no respondent, so the
#    verbatim question dictionary that CLAUDE.md makes mandatory "for every
#    survey" does not apply — exactly as it does not apply to V-Dem. What
#    replaces it is the CMP coding-scheme codebook (the per101–per706 category
#    definitions), stored under data/marpor/raw/<release>/.
#
# Pinned release: MPDS2025a (corpus version 2025-1).
#   The release MUST stay pinned. CMP revises scores between releases, and
#   Research & Politics expects a reproducible data citation — a floating
#   "current release" will not survive review.
#
# Source: manifesto-project.wzb.eu, via the manifestoR package.
#
# Credential
# ----------
# Requires a free MARPOR API key. It is stored in the macOS Keychain under
# service "marpor_api_key" and exported as MARPOR_API_KEY by ~/.secrets
# (which ~/.zshrc sources). marpor_apikey() below resolves it through a
# fallback chain so the module works both in an interactive shell and under a
# non-interactive `Rscript` call, which does NOT source ~/.zshrc:
#
#   1. Sys.getenv("MARPOR_API_KEY")           — interactive shells
#   2. macOS Keychain via `security`           — non-interactive Rscript
#   3. .secrets/manifesto_apikey.txt (gitignored, optional local override)
#
# The key is never written to the repo and never printed.

library(here)

MARPOR_RELEASE        <- "MPDS2025a"
MARPOR_CORPUS_VERSION <- "2025-1"

#' Resolve the MARPOR API key without ever printing it
marpor_apikey <- function() {

  k <- Sys.getenv("MARPOR_API_KEY")
  if (nzchar(k)) return(k)

  # Non-interactive Rscript does not source ~/.zshrc -> ~/.secrets, so read
  # the Keychain directly using the same service name ~/.secrets uses.
  if (Sys.info()[["sysname"]] == "Darwin") {
    k <- tryCatch(
      suppressWarnings(system2(
        "security",
        c("find-generic-password", "-a", Sys.info()[["user"]],
          "-s", "marpor_api_key", "-w"),
        stdout = TRUE, stderr = FALSE)),
      error = function(e) character(0))
    k <- trimws(paste(k, collapse = ""))
    if (nzchar(k)) return(k)
  }

  f <- here(".secrets", "manifesto_apikey.txt")
  if (file.exists(f)) {
    k <- trimws(readLines(f, warn = FALSE))[1]
    if (nzchar(k)) return(k)
  }

  stop("MARPOR API key not found. Expected one of:\n",
       "  - env var MARPOR_API_KEY (set by ~/.secrets)\n",
       "  - macOS Keychain service 'marpor_api_key'\n",
       "  - .secrets/manifesto_apikey.txt\n",
       "Obtain a free key at https://manifesto-project.wzb.eu")
}

#' Download the pinned MPDS release and cache it under data/marpor/raw/
#'
#' @param release  MPDS release id, pinned by default
#' @param refresh  if FALSE (default) and the cached .rds exists, read it back
#'                 instead of re-hitting the API
load_marpor_raw <- function(release = MARPOR_RELEASE,
                            corpus_version = MARPOR_CORPUS_VERSION,
                            refresh = FALSE) {

  raw_dir <- here("data", "marpor", "raw", release)
  dir.create(raw_dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(raw_dir, paste0(tolower(release), "_raw.rds"))

  if (!refresh && file.exists(path)) {
    cat("\n── MARPOR", release, "(cached) ──\n")
    d <- readRDS(path)
  } else {
    if (!requireNamespace("manifestoR", quietly = TRUE)) {
      stop("manifestoR is not installed. install.packages('manifestoR')")
    }
    cat("\n── Downloading MARPOR", release, "──\n")
    manifestoR::mp_setapikey(key = marpor_apikey())
    manifestoR::mp_use_corpus_version(corpus_version)
    d <- manifestoR::mp_maindataset(version = release)
    saveRDS(d, path)
    cat("  cached ->", path, "\n")
  }

  cat(sprintf("  %s rows × %d cols | %d countries | %d–%d\n",
              format(nrow(d), big.mark = ","), ncol(d),
              length(unique(d$countryname)),
              min(as.integer(substr(as.character(d$edate), 1, 4)), na.rm = TRUE),
              max(as.integer(substr(as.character(d$edate), 1, 4)), na.rm = TRUE)))
  d
}

#' The 56 standard CMP parent categories (per101 … per706).
#'
#' NB: manifestoR also exposes ~86 subcategory columns (per103_1, per608_3, …)
#' from the extended/5-digit scheme. Those break their PARENT down further, so
#' summing parents AND subcategories double-counts. Parity checks and any
#' multinomial reconstruction must use the parent set only.
marpor_parent_categories <- function(d) {
  grep("^per[0-9]{3}$", names(d), value = TRUE)
}

marpor_subcategories <- function(d) {
  grep("^per[0-9]{3}_", names(d), value = TRUE)
}

if (!interactive() && identical(environment(), globalenv())) {
  d <- load_marpor_raw()
  cat("\nparent categories:", length(marpor_parent_categories(d)),
      "| subcategories:", length(marpor_subcategories(d)), "\n")
}
