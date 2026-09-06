# Tests for the KGSS signature registry and its concept-group vocabulary.
# Run: Rscript src/scripts/prospector/test_signatures_kgss.R
suppressMessages(library(tidyverse)); library(yaml)
here_dir <- file.path("src", "scripts", "prospector")
source(file.path(here_dir, "signature_match.R"))

pass <- 0L; fail <- 0L
ok <- function(cond, msg) { if (isTRUE(cond)) { pass <<- pass + 1L } else { fail <<- fail + 1L; cat("FAIL:", msg, "\n") } }

kgss_sigs <- load_signatures(file.path(here_dir, "signatures_kgss.yml"))
abs_sigs  <- load_signatures(file.path(here_dir, "signatures.yml"))
kgss_grp  <- yaml.load_file(file.path("src", "scripts", "concept_groups_kgss.yml"))$concept_groups
abs_grp   <- yaml.load_file(file.path("src", "scripts", "concept_groups.yml"))$concept_groups

# Every group a signature names, across every clause type.
groups_named <- function(s) {
  unique(c(names(s$required), names(s$supporting), names(s$level), names(s$within),
           unlist(lapply(s$ordered, function(o) o$group))))
}
vars_named <- function(s) unlist(lapply(s$within, names), use.names = FALSE)

# ── the bug this registry fixes ─────────────────────────────────────────────
# A KGSS run pointed at signatures.yml could never match anything, because that
# file is written in the ABS group vocabulary. Guard the invariant in both
# directions so a future edit to either file cannot silently reintroduce it.
kgss_unknown <- setdiff(unlist(lapply(kgss_sigs, groups_named)), names(kgss_grp))
ok(length(kgss_unknown) == 0,
   paste("KGSS signatures reference only KGSS groups; strays:", paste(kgss_unknown, collapse = ", ")))
abs_unknown <- setdiff(unlist(lapply(abs_sigs, groups_named)), names(abs_grp))
ok(length(abs_unknown) == 0,
   paste("ABS signatures reference only ABS groups; strays:", paste(abs_unknown, collapse = ", ")))

kgss_all_vars <- unlist(kgss_grp, use.names = FALSE)
kgss_bad_vars <- setdiff(unlist(lapply(kgss_sigs, vars_named)), kgss_all_vars)
ok(length(kgss_bad_vars) == 0,
   paste("every KGSS `within` variable belongs to a KGSS group; strays:", paste(kgss_bad_vars, collapse = ", ")))

ok(length(kgss_sigs) >= 15, "KGSS registry is populated")
ok(all(vapply(kgss_sigs, function(s) is.character(s$label) && is.character(s$description),
              logical(1))), "every KGSS signature has a label and a description")

# ── concept-group hygiene: no group mixes valences ──────────────────────────
# imm_* and natid_shame and intl_world_govt_env run opposite to their former
# group-mates; pooling them made a uniform shift cancel to a flat, permanently
# DIVERGENT group. Assert the splits stayed split.
ok(!("immigration_attitudes" %in% names(kgss_grp)), "the valence-mixed immigration group is gone")
ok(all(c("immigration_threat", "immigration_benefit") %in% names(kgss_grp)),
   "immigration is split into threat and benefit")
ok(!("imm_help_econ" %in% kgss_grp$immigration_threat),
   "a pro-immigration item did not leak into the threat group")
ok(!("natid_shame" %in% kgss_grp$national_pride_general),
   "the inversely-valenced shame item is out of national_pride_general")
ok(!("intl_world_govt_env" %in% kgss_grp$international_attitudes),
   "the lone pro-globalism item is out of international_attitudes")
ok(all(lengths(kgss_grp) >= 2),
   "no group was reduced below the 2 members the coherence step requires")

# ── behaviour: representative signatures fire and don't over-fire ───────────
feq <- function(...) tribble(~country, ~group, ~group_direction, ...)

f1 <- feq("KOR", "conf_political", "FALLING", "KOR", "conf_civic_service", "FALLING")
ok("confidence_collapse" %in% match_signatures(f1, kgss_sigs)$pattern_id, "confidence_collapse fires")
f1b <- feq("KOR", "conf_political", "FALLING", "KOR", "conf_civic_service", "RISING")
ok(!("confidence_collapse" %in% match_signatures(f1b, kgss_sigs)$pattern_id),
   "confidence_collapse blocked when civic confidence rises")

f2 <- feq("KOR", "immigration_threat", "RISING", "KOR", "immigration_benefit", "FALLING")
ok("immigration_hardening" %in% match_signatures(f2, kgss_sigs)$pattern_id, "immigration_hardening fires")

# supporting clause: absent -> still fires; present and violated -> blocked
f3  <- feq("KOR", "corruption_perceptions", "RISING")
ok("anticorruption_decoupling" %in% match_signatures(f3, kgss_sigs)$pattern_id,
   "anticorruption_decoupling fires with the supporting group absent")
f3b <- feq("KOR", "corruption_perceptions", "RISING", "KOR", "corruption_performance", "FALLING")
ok(!("anticorruption_decoupling" %in% match_signatures(f3b, kgss_sigs)$pattern_id),
   "anticorruption_decoupling blocked when anti-corruption performance is itself falling")

# within clause needs variable-level slopes, not just group directions
fw <- feq("KOR", "political_efficacy", "FALLING")
vs <- tribble(~country, ~variable, ~direction,
              "KOR", "pol_efficacy_internal", "RISING",
              "KOR", "pol_efficacy_external", "FALLING")
ok("efficacy_trap_kr" %in% match_signatures(fw, kgss_sigs, var_slopes = vs)$pattern_id,
   "efficacy_trap_kr fires on variable-level directions")
ok(!("efficacy_trap_kr" %in% match_signatures(fw, kgss_sigs)$pattern_id),
   "efficacy_trap_kr cannot fire without variable-level data")

# a country with nothing moving should match nothing
fflat <- feq("KOR", "conf_political", "FLAT", "KOR", "conf_civic_service", "FLAT",
             "KOR", "political_action", "FLAT", "KOR", "wellbeing", "FLAT")
ok(nrow(match_signatures(fflat, kgss_sigs)) == 0, "an all-FLAT country matches no signature")

cat(sprintf("\n%d passed, %d failed\n", pass, fail))
if (fail > 0) quit(status = 1)
