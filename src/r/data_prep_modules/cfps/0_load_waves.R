# CFPS (China Family Panel Studies) — load raw ADULT waves into a wave-keyed list.
#
# SOURCE FILES (data/cfps/raw/unzipped/, from the PKU Dataverse deposit):
#   w2010  cfps2010_stata_chinese/.../cfps2010adult_202008.dta  (Stata, FULL value labels)
#   w2014  cfps2014_stata_chinese/.../cfps2014adult_201906.dta  (Stata, FULL value labels —
#          switched from the SAS variant 2026-08-09 when the Stata rar was downloaded.
#          ⚠️ The Stata release uses LOWERCASE variable names (qn1101, cfps_gender);
#          the SAS release upper-cases them (QN1101, CFPS_GENDER). Specs follow Stata.)
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
    "data", "cfps", "raw", "unzipped", "cfps2014_stata_chinese",
    "[CFPS Public Data] CFPS2014 in STATA (Chinese)", "cfps2014adult_201906.dta"),
  w2016 = file.path(
    "data", "cfps", "raw", "unzipped", "cfps2016_stata_chinese",
    "[CFPS Public Data] CFPS2016 in STATA (Chinese)", "cfps2016adult_201906.dta"),
  w2018 = file.path(
    "data", "cfps", "raw", "unzipped", "cfps2018_stata_chinese",
    "extracted", "cfps2018person_202012.dta"),
  w2020 = file.path(
    "data", "cfps", "raw", "unzipped", "cfps2020_stata_chinese",
    "[CFPS Public Data] CFPS 2020_in_STATA_(Chinese)", "cfps2020person_202306.dta"),
  w2022 = file.path(
    "data", "cfps", "raw", "unzipped", "cfps2022_stata_chinese",
    "extracted", "CFPS2022Stata_解密信息参见Instructions", "cfps2022person_202410.dta")
)

# From 2018 CFPS unifies adult + child questionnaires into one `person` module
# that includes children from ~age 9. To keep the harmonized file an ADULT
# frame consistent with the 2010-2016 adult modules, person waves are filtered
# to age >= 16 at load (the political modules are not asked below that anyway).
.CFPS_PERSON_WAVES <- c("w2018", "w2020", "w2022")

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
    n_raw <- nrow(d)
    if (wname %in% .CFPS_PERSON_WAVES) {
      age_num <- as.numeric(haven::zap_labels(d$age))
      d <- d[!is.na(age_num) & age_num >= 16, , drop = FALSE]
    }
    waves[[wname]] <- d
    cat(sprintf("  %s: %s rows%s, %d cols  (%s)\n",
                wname, format(nrow(d), big.mark = ","),
                if (nrow(d) < n_raw)
                  sprintf(" (person module: %s under-16 rows dropped)",
                          format(n_raw - nrow(d), big.mark = ","))
                else "",
                ncol(d), basename(path)))
  }

  waves
}
