# WVS: Load wave data
# W1-W5: SPSS .sav files via haven
# W6-W7: Apache Parquet CACHE, rebuilt from the .sav when absent
# Creates wave list ready for harmonization

library(arrow)
library(haven)
library(here)

#' Read a wave from a parquet cache, regenerating it from the .sav if missing.
#'
#' W6/W7 are large, so an early session converted them to parquet for speed and
#' the loader has read parquet ever since. But nothing in the repo produced those
#' files, so once they were deleted WVS became unbuildable: `2_harmonize_all.R`
#' died with "Failed to open local file ... wvs_wave6.parquet" while the .sav it
#' was derived from sat right next to it. (Surfaced 2026-07-09 by
#' src/r/audit/06_check_freshness.R, which reported wvs STALE with two missing
#' inputs.)
#'
#' The cache is a pure derivative of the .sav — labels are dropped either way,
#' since the harmonization engine reads values and the label-reconciliation audit
#' re-reads the .sav itself for metadata.
.wvs_read_cached <- function(parquet_path, sav_path) {
  if (!file.exists(parquet_path)) {
    if (!file.exists(sav_path)) {
      stop("WVS: neither the parquet cache nor its source .sav exists:\n  ",
           parquet_path, "\n  ", sav_path, call. = FALSE)
    }
    cat(sprintf("(cache miss: rebuilding %s from %s) ",
                basename(parquet_path), basename(sav_path)))
    df <- haven::read_sav(sav_path, encoding = "latin1")
    df <- haven::zap_labels(df)
    dir.create(dirname(parquet_path), recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(df, parquet_path)
    return(df)
  }
  arrow::read_parquet(parquet_path)
}

#' Load WVS wave data
#'
#' Loads waves 1-7: W1-W5 from SPSS .sav, W6-W7 from parquet.
#' Returns a named list compatible with the harmonization engine.
#'
#' @return List of 7 dataframes (w1, w2, w3, w4, w5, w6, w7)
#' @export
load_wvs_waves <- function() {

  # W1-W5: SPSS .sav files
  sav_waves <- list(
    w1 = here("data", "wvs", "raw", "wave1", "WV1_Data_spss_v20200208.sav"),
    w2 = here("data", "wvs", "raw", "wave2", "WV2_Data_Spss_v20180912.sav"),
    w3 = here("data", "wvs", "raw", "wave3", "WV3_Data_Spss_v20180912.sav"),
    w4 = here("data", "wvs", "raw", "wave4", "WV4_Data_spss_v20201117.sav"),
    w5 = here("data", "wvs", "raw", "wave5", "WV5_Data_Spss_v20180912.sav")
  )

  # W6-W7: parquet cache, regenerated from the .sav beside it when missing
  parquet_waves <- list(
    w6 = here("data", "wvs", "raw", "wave6", "wvs_wave6.parquet"),
    w7 = here("data", "wvs", "raw", "wave7", "wvs_wave7.parquet")
  )
  parquet_sources <- list(
    w6 = here("data", "wvs", "raw", "wave6", "WV6_Data_sav_v20201117.sav"),
    w7 = here("data", "wvs", "raw", "wave7", "WVS_Cross-National_Wave_7_spss_v6_0.sav")
  )

  waves <- list()

  # Load .sav waves
  for (wave_name in names(sav_waves)) {
    path <- sav_waves[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- haven::read_sav(path, encoding = "latin1")
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
  }

  # Load parquet waves (cache; rebuilt from .sav on miss)
  for (wave_name in names(parquet_waves)) {
    path <- parquet_waves[[wave_name]]
    cat(sprintf("Loading %s from %s ... ", wave_name, basename(path)))
    df <- .wvs_read_cached(path, parquet_sources[[wave_name]])
    waves[[wave_name]] <- df
    cat(sprintf("%s rows, %s cols\n",
                format(nrow(df), big.mark = ","), ncol(df)))
  }

  cat(sprintf("\nLoaded %d WVS waves\n", length(waves)))
  waves
}
