suppressMessages(library(tidyverse)); library(yaml)
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "signature_match.R"))
pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

sigs <- load_signatures(file.path(here_dir, "signatures.yml"))
ok(length(sigs) == 14, "14 signatures loaded")
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

# absent REQUIRED group -> signature must NOT fire
f_absent_req <- tribble(~country, ~group,                            ~group_direction,
                        "R1",      "institutional_trust_executive",  "FALLING")  # intermediary missing
ok(!("trust_collapse" %in% match_signatures(f_absent_req, sigs)$pattern_id),
   "trust_collapse blocked when a required group is absent")

# absent SUPPORTING group -> signature still fires (supporting not penalised)
f_absent_sup <- tribble(~country, ~group,                             ~group_direction,
                        "R2",      "democracy_assessment_empirical",   "FALLING")  # normative (supporting) missing
ok("aspiration_gap" %in% match_signatures(f_absent_sup, sigs)$pattern_id,
   "aspiration_gap fires when the supporting group is absent")

sigs <- load_signatures(file.path(here_dir, "signatures.yml"))  # reload with new entries
feq <- function(...) tribble(~country, ~group, ~group_direction, ...) %>% mutate(country=as.character(country))

# authoritarian_drift: normative FALLING + authoritarian RISING
f1 <- feq("A","democracy_support_normative","FALLING", "A","authoritarian_support","RISING")
ok("authoritarian_drift" %in% match_signatures(f1, sigs)$pattern_id, "authoritarian_drift fires")

# diffuse_specific_decoupling: satisfaction FALLING, normative FLAT (supporting)
f2 <- feq("B","democratic_satisfaction","FALLING", "B","democracy_support_normative","FLAT")
ok("diffuse_specific_decoupling" %in% match_signatures(f2, sigs)$pattern_id, "diffuse_specific fires")
# negative control: normative FALLING violates supporting
f2b <- feq("C","democratic_satisfaction","FALLING", "C","democracy_support_normative","FALLING")
ok(!("diffuse_specific_decoupling" %in% match_signatures(f2b, sigs)$pattern_id), "diffuse_specific blocked by falling normative")

# accountable_dissatisfaction (health): satisfaction + exec trust FALLING, normative RISING
f3 <- feq("D","democratic_satisfaction","FALLING", "D","institutional_trust_executive","FALLING",
          "D","democracy_support_normative","RISING")
ok("accountable_dissatisfaction" %in% match_signatures(f3, sigs)$pattern_id, "accountable_dissatisfaction fires")

# rule_of_law_erosion: rule_of_law FALLING (supporting accountability_perceptions FALLING/FLAT)
f4 <- feq("E","rule_of_law","FALLING", "E","accountability_perceptions","FLAT")
ok("rule_of_law_erosion" %in% match_signatures(f4, sigs)$pattern_id, "rule_of_law_erosion fires")

# alienation_withdrawal: efficacy FALLING + contacting/protest FALLING
f5 <- feq("F","political_efficacy","FALLING", "F","political_action_contacting_protest","FALLING")
ok("alienation_withdrawal" %in% match_signatures(f5, sigs)$pattern_id, "alienation_withdrawal fires")

# output_trust_legitimation: economic_present RISING + exec trust RISING (supporting empirical FALLING/FLAT)
f6 <- feq("G","economic_present","RISING", "G","institutional_trust_executive","RISING",
          "G","democracy_assessment_empirical","FALLING")
ok("output_trust_legitimation" %in% match_signatures(f6, sigs)$pattern_id, "output_trust_legitimation fires")

# Behavior-lock: the 8 ORIGINAL signatures must reproduce their frozen ABS matches,
# even as new signatures/features are added. Reads committed fixtures (portable).
orig8 <- c("output_legitimacy","demobilization","aspiration_gap","hollow_citizenship",
           "trust_collapse","selective_legitimation","economic_pessimism","corruption_normalization")
fx_dir <- file.path(here_dir, "testdata")
sg   <- readr::read_csv(file.path(fx_dir, "abs_slope_groups.golden.csv"), show_col_types = FALSE)
gold <- readr::read_csv(file.path(fx_dir, "abs_narrative_8sig.golden.csv"), show_col_types = FALSE)
feats_real <- sg %>% dplyr::select(country, group, group_direction) %>% dplyr::mutate(country = as.character(country))
got <- match_signatures(feats_real, sigs) %>%
  dplyr::filter(pattern_id %in% orig8) %>%
  dplyr::mutate(country = as.character(country)) %>%
  dplyr::arrange(country, pattern_id)
gold2 <- gold %>% dplyr::mutate(country = as.character(country)) %>%
  dplyr::select(country, pattern_id) %>% dplyr::arrange(country, pattern_id)
ok(identical(got$pattern_id, gold2$pattern_id) && identical(got$country, gold2$country),
   "behavior-lock: 8 original signatures reproduce frozen ABS golden")

source(file.path(here_dir, "signature_features.R"))
# synthetic: flat at 0.2 for waves 1-3, jump to 0.8 waves 4-6 -> break near wave 3/4
synth <- tidyr::expand_grid(country="Z", variable="v", wave_num=1:6) %>%
  mutate(mean_value = if_else(wave_num <= 3, 0.2, 0.8))
sb <- tibble(country="Z", variable="v")
bl <- augment_breaks_with_location(synth, sb)
ok(nrow(bl) == 1 && !is.na(bl$break_wave) && bl$break_wave %in% c(3,4), "break located at wave 3 or 4")

cat(sprintf("\n%d passed, %d failed\n", pass, fail)); if (fail > 0) quit(status = 1)
