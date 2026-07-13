suppressMessages(library(tidyverse)); library(yaml)
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "signature_match.R"))
pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

sigs <- load_signatures(file.path(here_dir, "signatures.yml"))
ok(length(sigs) == 27, "27 signatures loaded")
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

thr <- list(FAST = 0.15, ENDS_LOW = 0.33, ENDS_HIGH = 0.66, SHAPE_QUORUM = 0.5)
gl  <- tibble(group = "g", variable = c("a","b"))
gc  <- tibble(country="Z", group="g", group_direction="RISING", mean_slope=0.20,
              sd_slope=0, n_vars=2, coherence_flag="COHERENT_RISING")
# endpoints: both members end high (0.8)
hd  <- tidyr::expand_grid(country="Z", variable=c("a","b"), wave_num=1:3) %>%
  mutate(mean_value = if_else(wave_num==3, 0.8, 0.3))
acc <- tibble(country="Z", variable=c("a","b"),
              early_slope=c(-0.1,-0.1), late_slope=c(0.3,0.3),
              acceleration=c(0.4,0.4), direction_change=c(TRUE,TRUE))
bl  <- tibble(country="Z", variable=c("a","b"), break_wave=c(2,2))
gf  <- build_group_features(gc, hd, acc, bl, gl, thr)
ok(gf$magnitude_tier == "FAST", "magnitude FAST (|0.20|>0.15)")
ok(gf$ends_level == "HIGH", "ends_level HIGH (0.8>0.66)")
ok(gf$shape == "REVERSED_UP", "shape REVERSED_UP (down then up)")
ok(gf$broke_at_wave == 2, "broke_at_wave = 2 (modal)")

vs <- tibble(country="W", variable=c("efficacy_ability_participate","efficacy_no_influence"),
             direction=c("RISING","RISING"))
within_spec <- list(political_efficacy = list(efficacy_ability_participate="RISING",
                                              efficacy_no_influence="RISING"))
ok(eval_within(within_spec, vs, "W"), "within fires when all sub-vars match")
vs2 <- vs %>% mutate(direction = c("RISING","FALLING"))
ok(!eval_within(within_spec, vs2, "W"), "within blocked when one sub-var mismatches")

fo <- tribble(~country,~group,~group_direction,~broke_at_wave,
  "S","political_action_contacting_protest","FALLING",3,
  "S","authoritarian_support","RISING",4)
ordered_spec <- list(list(group="political_action_contacting_protest", dir="FALLING"),
                     list(group="authoritarian_support", dir="RISING"))
ok(eval_ordered(ordered_spec, fo, "S"), "ordered fires when protest breaks before authoritarian rise")
fo2 <- fo %>% mutate(broke_at_wave = c(5,4))  # protest breaks AFTER
ok(!eval_ordered(ordered_spec, fo2, "S"), "ordered blocked when order reversed")

# ── Phase 2 acceptance tests: coup_honeymoon, accelerating_trust_collapse ──
sigs <- load_signatures(file.path(here_dir, "signatures.yml"))  # reload with Phase-2 entries

# coup honeymoon: authoritarian_support shape REVERSED_UP
fh <- tribble(~country,~group,~group_direction,~magnitude_tier,~shape,~ends_level,~broke_at_wave,
  "TH","authoritarian_support","FLAT","SLOW","REVERSED_UP","MID",NA_real_)
ok("coup_honeymoon" %in% match_signatures(fh, sigs)$pattern_id, "coup_honeymoon fires on REVERSED_UP")

# accelerating trust collapse
fc <- tribble(~country,~group,~group_direction,~magnitude_tier,~shape,~ends_level,~broke_at_wave,
  "SWZ","institutional_trust_executive","FALLING","FAST","STEADY","LOW",8,
  "SWZ","institutional_trust_intermediary","FALLING","SLOW","STEADY","LOW",8)
ok("accelerating_trust_collapse" %in% match_signatures(fc, sigs)$pattern_id, "accelerating_trust_collapse fires")
# negative control: magnitude SLOW
fc2 <- fc %>% mutate(magnitude_tier = if_else(group=="institutional_trust_executive","SLOW",magnitude_tier))
ok(!("accelerating_trust_collapse" %in% match_signatures(fc2, sigs)$pattern_id), "blocked when exec not FAST")

# --- Phase-2 signature firing tests (prove each new signature can fire) ---

# authoritarian_ascendant: authoritarian_support RISING at a HIGH level
fa <- tibble(country="AA", group="authoritarian_support", group_direction="RISING",
             magnitude_tier="SLOW", shape="STEADY", ends_level="HIGH", broke_at_wave=NA_real_)
ok("authoritarian_ascendant" %in% match_signatures(fa, sigs)$pattern_id,
   "authoritarian_ascendant fires (RISING + level HIGH)")
ok(!("authoritarian_ascendant" %in% match_signatures(dplyr::mutate(fa, ends_level="MID"), sigs)$pattern_id),
   "authoritarian_ascendant blocked when level not HIGH")

# true_demobilization_sequence: protest breaks (FALLING) before authoritarian_support rises
fd <- tribble(~country, ~group,                                  ~group_direction, ~broke_at_wave,
              "DD",     "political_action_contacting_protest",   "FALLING",        3,
              "DD",     "authoritarian_support",                 "RISING",         5)
ok("true_demobilization_sequence" %in% match_signatures(fd, sigs)$pattern_id,
   "true_demobilization_sequence fires (protest breaks before authoritarian rise)")
ok(!("true_demobilization_sequence" %in% match_signatures(dplyr::mutate(fd, broke_at_wave=c(5,3)), sigs)$pattern_id),
   "true_demobilization_sequence blocked when break order reversed")

# efficacy_trap: within political_efficacy, feel able to participate (RISING) yet no influence (RISING)
fe_feats <- tibble(country="EE", group="political_efficacy", group_direction="FLAT",
                   magnitude_tier="SLOW", shape="STEADY", ends_level="MID", broke_at_wave=NA_real_)
fe_vs  <- tibble(country="EE", variable=c("efficacy_ability_participate","efficacy_no_influence"),
                 direction=c("RISING","RISING"))
ok("efficacy_trap" %in% match_signatures(fe_feats, sigs, var_slopes=fe_vs)$pattern_id,
   "efficacy_trap fires (able to participate but no influence)")
fe_vs2 <- dplyr::mutate(fe_vs, direction=c("RISING","FALLING"))
ok(!("efficacy_trap" %in% match_signatures(fe_feats, sigs, var_slopes=fe_vs2)$pattern_id),
   "efficacy_trap blocked when one sub-variable mismatches")

# eval_ordered negative controls (missing group / NA break wave / direction mismatch)
fo_missing <- tribble(~country, ~group,                                ~group_direction, ~broke_at_wave,
                      "OM",     "political_action_contacting_protest", "FALLING",        3)
ok(!("true_demobilization_sequence" %in% match_signatures(fo_missing, sigs)$pattern_id),
   "true_demobilization_sequence blocked when a sequenced group is absent")
fo_na <- tribble(~country, ~group,                                ~group_direction, ~broke_at_wave,
                 "ON",     "political_action_contacting_protest", "FALLING",        NA_real_,
                 "ON",     "authoritarian_support",               "RISING",         5)
ok(!("true_demobilization_sequence" %in% match_signatures(fo_na, sigs)$pattern_id),
   "true_demobilization_sequence blocked when a break wave is NA")
fo_dir <- tribble(~country, ~group,                                ~group_direction, ~broke_at_wave,
                  "OD",     "political_action_contacting_protest", "RISING",         3,
                  "OD",     "authoritarian_support",                "RISING",         5)
ok(!("true_demobilization_sequence" %in% match_signatures(fo_dir, sigs)$pattern_id),
   "true_demobilization_sequence blocked when a group's direction is wrong")

# selective_accountability end-to-end firing test
sa_feats <- tibble(country="SA", group="accountability_perceptions", group_direction="FLAT",
                   magnitude_tier="SLOW", shape="STEADY", ends_level="MID", broke_at_wave=NA_real_)
sa_vs <- tibble(country="SA", variable=c("gov_elections_real_choice","gov_courts_powerless"),
                direction=c("RISING","RISING"))
ok("selective_accountability" %in% match_signatures(sa_feats, sigs, var_slopes=sa_vs)$pattern_id,
   "selective_accountability fires (elections real choice up while courts powerless up)")

# ── Pass A rider-signature firing + negative-control tests ──
sigs <- load_signatures(file.path(here_dir, "signatures.yml"))   # full 27-signature registry
ok("illiberal_drift" %in% match_signatures(tibble(country="IL", group="illiberal_values", group_direction="RISING"), sigs)$pattern_id,
   "illiberal_drift fires (illiberal_values RISING)")
ok("anti_pluralist_turn" %in% match_signatures(tibble(country="AP", group="anti_pluralism", group_direction="RISING"), sigs)$pattern_id,
   "anti_pluralist_turn fires (anti_pluralism RISING)")
ok("system_support_erosion" %in% match_signatures(tibble(country="SS", group="system_support", group_direction="FALLING"), sigs)$pattern_id,
   "system_support_erosion fires (system_support FALLING)")
ok("value_modernization" %in% match_signatures(tibble(country="VM", group="traditional_authority", group_direction="FALLING"), sigs)$pattern_id,
   "value_modernization fires (traditional_authority FALLING)")
ok("economic_nationalist_turn" %in% match_signatures(tibble(country="EN", group="economic_nationalism", group_direction="RISING"), sigs)$pattern_id,
   "economic_nationalist_turn fires (economic_nationalism RISING)")
ok(!("economic_nationalist_turn" %in% match_signatures(tibble(country="ENB", group="economic_nationalism", group_direction="FALLING"), sigs)$pattern_id),
   "economic_nationalist_turn blocked when economic_nationalism not RISING")
ok("mobility_pessimism" %in% match_signatures(tibble(country="MP", group="social_mobility", group_direction="FALLING"), sigs)$pattern_id,
   "mobility_pessimism fires (social_mobility FALLING)")
gf_paradox <- tribble(~country, ~group,                   ~group_direction,
                      "PX",      "traditional_authority",  "FALLING",
                      "PX",      "illiberal_values",        "RISING")
ok("illiberal_modernization_paradox" %in% match_signatures(gf_paradox, sigs)$pattern_id,
   "illiberal_modernization_paradox fires (trad_authority FALLING + illiberal_values RISING)")
ok(!("illiberal_modernization_paradox" %in% match_signatures(tibble(country="PXB", group="traditional_authority", group_direction="FALLING"), sigs)$pattern_id),
   "illiberal_modernization_paradox blocked when illiberal_values not RISING")

cat(sprintf("\n%d passed, %d failed\n", pass, fail)); if (fail > 0) quit(status = 1)
