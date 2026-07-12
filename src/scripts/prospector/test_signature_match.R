suppressMessages(library(tidyverse)); library(yaml)
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "signature_match.R"))
pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

sigs <- load_signatures(file.path(here_dir, "signatures.yml"))
ok(length(sigs) == 8, "8 signatures loaded")
ok(identical(sigs$aspiration_gap$required$democracy_assessment_empirical, "FALLING"), "aspiration_gap required dir")
ok(setequal(unlist(sigs$output_legitimacy$supporting$democracy_assessment_empirical), c("FALLING","FLAT")), "output_legitimacy supporting vector")

# normalize_condition
ok(identical(normalize_condition("FALLING"), list(dir = "FALLING")), "string -> dir list")
ok(setequal(normalize_condition(list("RISING","FLAT"))$dir, c("RISING","FLAT")), "unnamed list -> dir vector")
ok(identical(normalize_condition(list(dir="RISING", level="ENDS_HIGH"))$level, "ENDS_HIGH"), "named cond passthrough")

# match_signatures on a synthetic feature frame
feats <- tribble(
  ~country, ~group,                              ~group_direction,
  "X",      "institutional_trust_executive",     "FALLING",
  "X",      "institutional_trust_intermediary",  "FALLING",
  "Y",      "institutional_trust_executive",     "RISING",
  "Y",      "institutional_trust_intermediary",  "FALLING"
)
m <- match_signatures(feats, sigs)
ok("trust_collapse" %in% m$pattern_id[m$country=="X"], "X fires trust_collapse")
ok(!("trust_collapse" %in% m$pattern_id[m$country=="Y"]), "Y does not fire trust_collapse")
ok("selective_legitimation" %in% m$pattern_id[m$country=="Y"], "Y fires selective_legitimation")
