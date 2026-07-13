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
    if (!is.null(slot$dir))        slot$dir        <- unlist(slot$dir)
    if (!is.null(slot$magnitude))  slot$magnitude  <- unlist(slot$magnitude)
    if (!is.null(slot$shape))      slot$shape      <- unlist(slot$shape)
    if (!is.null(slot$level))      slot$level      <- unlist(slot$level)
    if (!is.null(slot$coherence))  slot$coherence  <- unlist(slot$coherence)
    if (!is.null(slot$volatility)) slot$volatility <- unlist(slot$volatility)
    if (!is.null(slot$curvature))  slot$curvature  <- unlist(slot$curvature)
    return(slot)
  }
  list(dir = as.character(slot))
}

# Evaluate one condition against one feature-frame row (a 1-row tibble/list).
# Every sub-key present in the condition AND available in the row must hold.
eval_simple_condition <- function(cond, row) {
  cond_n <- normalize_condition(cond)
  checks <- c(
    if (!is.null(cond_n$dir))       row$group_direction %in% cond_n$dir,
    if (!is.null(cond_n$magnitude) && !is.null(row$magnitude_tier)) row$magnitude_tier %in% cond_n$magnitude,
    if (!is.null(cond_n$shape)     && !is.null(row$shape))          row$shape          %in% cond_n$shape,
    if (!is.null(cond_n$level)     && !is.null(row$ends_level))     row$ends_level     %in% cond_n$level,
    if (!is.null(cond_n$coherence)  && !is.null(row$coherence))     row$coherence      %in% cond_n$coherence,
    if (!is.null(cond_n$volatility) && !is.null(row$volatility))    row$volatility     %in% cond_n$volatility,
    if (!is.null(cond_n$curvature)  && !is.null(row$curvature))     row$curvature      %in% cond_n$curvature
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

# level: a group-level top-level clause (Phase 2). Each value must be wrapped
# as {level: value} before evaluation — `eval_simple_condition`'s bare-string
# handling treats an unwrapped scalar as a `dir` clause, not a `level` clause.
.eval_level <- function(levels, features, cty) {
  if (length(levels) == 0) return(TRUE)
  all(vapply(names(levels), function(g) {
    row <- .row_for(features, cty, g)
    !is.null(row) && eval_simple_condition(list(level = levels[[g]]), row)
  }, logical(1)))
}

# within: every named sub-variable in the group must match its direction.
eval_within <- function(within_spec, var_slopes, cty) {
  if (is.null(within_spec) || length(within_spec) == 0) return(TRUE)
  if (is.null(var_slopes)) return(FALSE)   # a within-signature cannot fire without variable-level data
  vs <- var_slopes[var_slopes$country == cty, , drop = FALSE]
  all(vapply(names(within_spec), function(grp) {
    reqs <- within_spec[[grp]]
    all(vapply(names(reqs), function(v) {
      d <- vs$direction[vs$variable == v]
      length(d) == 1 && d %in% unlist(reqs[[v]])
    }, logical(1)))
  }, logical(1)))
}

# ordered: list in temporal order; each group's break wave must be non-NA,
# its group_direction must match dir, and break waves must be non-decreasing.
eval_ordered <- function(ordered_spec, features, cty) {
  if (is.null(ordered_spec) || length(ordered_spec) == 0) return(TRUE)
  rows <- lapply(ordered_spec, function(item) .row_for(features, cty, item$group))
  if (any(vapply(rows, is.null, logical(1)))) return(FALSE)
  waves <- vapply(rows, function(r) as.numeric(r$broke_at_wave %||% NA), numeric(1))
  if (any(is.na(waves))) return(FALSE)
  dirs_ok <- all(mapply(function(item, r) r$group_direction %in% unlist(item$dir),
                        ordered_spec, rows))
  dirs_ok && all(diff(waves) >= 0)
}

match_signatures <- function(features, sigs, var_slopes = NULL) {
  countries <- unique(features$country)
  out <- purrr::map_dfr(countries, function(cty) {
    purrr::map_dfr(names(sigs), function(pid) {
      s <- sigs[[pid]]
      req <- .eval_required(s$required %||% list(), features, cty)
      sup <- .eval_supporting(s$supporting %||% list(), features, cty)
      lvl <- .eval_level(s$level %||% list(), features, cty)         # Phase 2
      wth <- eval_within(s$within, var_slopes, cty)
      ord <- eval_ordered(s$ordered, features, cty)
      if (req && sup && lvl && wth && ord)
        tibble(country = cty, pattern_id = pid, label = s$label, description = s$description)
      else tibble()
    })
  })
  if (nrow(out) == 0) return(tibble(country=character(), pattern_id=character(),
                                    label=character(), description=character()))
  dplyr::arrange(out, country, pattern_id)
}
