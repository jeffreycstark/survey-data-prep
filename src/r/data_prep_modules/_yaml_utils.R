# Shared YAML utilities for data prep modules

#' List all YAML spec files
#'
#' @param config_dir Directory containing YAML specs
#' @return Character vector of YAML file paths
list_yaml_specs <- function(config_dir = here::here("src/config/harmonize_validated")) {
  files <- list.files(config_dir, pattern = "\\.yml$", full.names = TRUE)

  # Exclude template and documentation files
  exclude_patterns <- c("MODEL_VARIABLE", "TEMPLATE", "README")
  files <- files[!grepl(paste(exclude_patterns, collapse = "|"), files, ignore.case = TRUE)]

  files
}
