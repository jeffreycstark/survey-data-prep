# Signature registry loader + condition evaluator for the Slope Prospector.
library(yaml)

load_signatures <- function(path) {
  raw <- yaml.load_file(path)
  raw$signatures
}

# A slot is: a scalar direction, an unnamed list/vector of directions, or a
# named condition map {dir=, magnitude=, shape=, level=}.
normalize_condition <- function(slot) {
  if (is.character(slot)) return(list(dir = slot))
  if (is.list(slot) && is.null(names(slot))) return(list(dir = unlist(slot)))
  if (is.list(slot)) {
    if (!is.null(slot$dir))       slot$dir       <- unlist(slot$dir)
    if (!is.null(slot$magnitude)) slot$magnitude <- unlist(slot$magnitude)
    if (!is.null(slot$shape))     slot$shape     <- unlist(slot$shape)
    if (!is.null(slot$level))     slot$level     <- unlist(slot$level)
    return(slot)
  }
  list(dir = as.character(slot))
}

# Evaluate one condition against one feature-frame row (a 1-row tibble/list).
# Every sub-key present in the condition AND available in the row must hold.
eval_simple_condition <- function(cond, row) {
  c <- normalize_condition(cond)
  checks <- c(
    if (!is.null(c$dir))       row$group_direction %in% c$dir,
    if (!is.null(c$magnitude) && !is.null(row$magnitude_tier)) row$magnitude_tier %in% c$magnitude,
    if (!is.null(c$shape)     && !is.null(row$shape))          row$shape          %in% c$shape,
    if (!is.null(c$level)     && !is.null(row$ends_level))     row$ends_level     %in% c$level
  )
  length(checks) > 0 && all(checks)
}

.row_for <- function(features, cty, grp) {
  r <- features[features$country == cty & features$group == grp, , drop = FALSE]
  if (nrow(r) == 0) return(NULL)
  as.list(r[1, ])
}

# required: group must be present AND condition holds.
# supporting: if group absent, don't penalise; if present, condition must hold.
.eval_required <- function(reqs, features, cty) {
  if (length(reqs) == 0) return(TRUE)
  all(vapply(names(reqs), function(g) {
    row <- .row_for(features, cty, g); !is.null(row) && eval_simple_condition(reqs[[g]], row)
  }, logical(1)))
}
.eval_supporting <- function(sups, features, cty) {
  if (length(sups) == 0) return(TRUE)
  all(vapply(names(sups), function(g) {
    row <- .row_for(features, cty, g); is.null(row) || eval_simple_condition(sups[[g]], row)
  }, logical(1)))
}

match_signatures <- function(features, sigs, var_slopes = NULL) {
  countries <- unique(features$country)
  out <- purrr::map_dfr(countries, function(cty) {
    purrr::map_dfr(names(sigs), function(pid) {
      s <- sigs[[pid]]
      req <- .eval_required(s$required %||% list(), features, cty)
      sup <- .eval_supporting(s$supporting %||% list(), features, cty)
      lvl <- .eval_required(s$level %||% list(), features, cty)      # Phase 2, treated as required
      if (req && sup && lvl)
        tibble(country = cty, pattern_id = pid, label = s$label, description = s$description)
      else tibble()
    })
  })
  if (nrow(out) == 0) return(tibble(country=character(), pattern_id=character(),
                                    label=character(), description=character()))
  dplyr::arrange(out, country, pattern_id)
}
