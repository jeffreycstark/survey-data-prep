#' Generate comprehensive descriptive statistics
#' 
#' @param data Data frame or tibble
#' @param .vars Optional. Variables to describe. If NULL, describes all.
#' @return Tibble with descriptive statistics
#' @export
describe_data <- function(data, .vars = NULL) {
  
  require(tidyverse)
  
  if (!is.null(.vars)) {
    data <- data %>% select(all_of(.vars))
  }
  
  # Generate statistics
  desc <- data %>%
    summarise(across(
      everything(),
      list(
        n = ~sum(!is.na(.)),
        missing = ~sum(is.na(.)),
        missing_pct = ~mean(is.na(.)) * 100,
        unique = ~n_distinct(., na.rm = TRUE),
        mean = ~if(is.numeric(.)) mean(., na.rm = TRUE) else NA_real_,
        sd = ~if(is.numeric(.)) sd(., na.rm = TRUE) else NA_real_,
        min = ~if(is.numeric(.)) min(., na.rm = TRUE) else NA_real_,
        max = ~if(is.numeric(.)) max(., na.rm = TRUE) else NA_real_
      ),
      .names = "{.col}__{.fn}"
    )) %>%
    pivot_longer(
      everything(),
      names_to = c("variable", "statistic"),
      names_sep = "__",
      values_to = "value"
    ) %>%
    pivot_wider(
      names_from = statistic,
      values_from = value
    )
  
  return(desc)
}

#' Create publication-ready descriptive statistics table
#' 
#' @param data Data frame or tibble
#' @param .vars Variables to include
#' @param .labels Named vector of variable labels
#' @return gt table object
#' @export
make_table1 <- function(data, .vars = NULL, .labels = NULL) {
  
  require(tidyverse)
  require(gtsummary)
  
  if (!is.null(.vars)) {
    data <- data %>% select(all_of(.vars))
  }
  
  # Create base table
  tbl <- data %>%
    tbl_summary(
      statistic = list(
        all_continuous() ~ "{mean} ({sd})",
        all_categorical() ~ "{n} ({p}%)"
      ),
      digits = all_continuous() ~ 2,
      label = .labels
    ) %>%
    modify_header(label ~ "**Variable**") %>%
    modify_caption("**Table 1. Descriptive Statistics**") %>%
    bold_labels()
  
  return(tbl)
}

#' Quick frequency table
#' 
#' @param data Data frame
#' @param var Variable name (unquoted)
#' @return Frequency table
#' @export
freq_table <- function(data, var) {
  
  require(tidyverse)
  
  data %>%
    count({{ var }}) %>%
    mutate(
      pct = n / sum(n) * 100,
      cum_pct = cumsum(pct)
    ) %>%
    arrange(desc(n))
}

