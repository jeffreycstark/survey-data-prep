suppressMessages(library(tidyverse)); library(yaml)
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "signature_match.R"))
pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

sigs <- load_signatures(file.path(here_dir, "signatures.yml"))
ok(length(sigs) == 8, "8 signatures loaded")
ok(identical(sigs$aspiration_gap$required$democracy_assessment_empirical, "FALLING"), "aspiration_gap required dir")
ok(setequal(unlist(sigs$output_legitimacy$supporting$democracy_assessment_empirical), c("FALLING","FLAT")), "output_legitimacy supporting vector")
