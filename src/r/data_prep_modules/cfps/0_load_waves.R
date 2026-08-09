# CFPS (China Family Panel Studies) — load raw ADULT waves into a wave-keyed list.
#
# SOURCE FILES (data/cfps/raw/unzipped/, from the PKU Dataverse deposit):
#   w2010  cfps2010_stata_chinese/.../cfps2010adult_202008.dta   (Stata, FULL value labels)
#   w2014  cfps2014_sas_chinese/.../cfps2014adult_201906.sas7bdat (SAS — variable labels
#          only: the deposit ships NO .sas7bcat catalogs, so the SAS files carry ZERO
#          value labels. The 2014 Stata variant was skipped by the Dataverse 100MB
#          bundle cap — see raw/MANIFEST.TXT. Re-download it to enable label checks.)
#
# NO SPSS (.sav) files exist for CFPS — the deposit is Stata + SAS only.
#
# DELIBERATELY NOT LOADED:
#   - 2008/2009 pre-survey pilots (cfps_presurvey/): different instruments; quarantined.
#   - child / famconf / famecon / comm modules: the harmonization targets adult
#     political attitudes (paper 26). Child-module dragons (born 2000/2012) have no
#     political items and are out of scope here.
#   - 2010 SAS variants (duplicate content of the .dta).
#
# PANEL NOTE: CFPS is a family panel — `pid` is the stable person key across waves.
# Rows are person-waves; do not treat them as independent respondents.

library(here)
library(haven)

.CFPS_FILES <- list(
  w2010 = file.path(
    "data", "cfps", "raw", "unzipped", "cfps2010_stata_chinese",
    "[CFPS Public Data] CFPS 2010 in Stata (Chinese)", "cfps2010adult_202008.dta"),
  w2014 = file.path(
    "data", "cfps", "raw", "unzipped", "cfps2014_sas_chinese",
    "[CFPS Public Data] CFPS2014 in SAS (Chinese)", "cfps2014adult_201906.sas7bdat")
)

load_cfps_waves <- function() {

  cat("\n── Loading CFPS raw adult waves ──\n")

  waves <- list()

  for (wname in names(.CFPS_FILES)) {
    path <- here(.CFPS_FILES[[wname]])
    if (!file.exists(path)) {
      stop("CFPS raw file not found: ", path,
           "\nUnpack the Dataverse download into data/cfps/raw/unzipped/ first.")
    }
    d <- switch(
      tools::file_ext(path),
      dta      = read_dta(path),
      sas7bdat = read_sas(path),
      stop("Unhandled CFPS file type: ", path)
    )
    waves[[wname]] <- d
    cat(sprintf("  %s: %s rows, %d cols  (%s)\n",
                wname, format(nrow(d), big.mark = ","), ncol(d), basename(path)))
  }

  waves
}
