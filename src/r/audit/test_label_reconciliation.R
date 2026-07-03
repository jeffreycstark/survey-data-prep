#!/usr/bin/env Rscript
# src/r/audit/test_label_reconciliation.R
#
# Regression + unit tests for the label-reconciliation check.
#
# Fixtures encode the two real 2026-06-20 bug classes so a future spec edit that
# reintroduces a wrong-direction fn on an inverse-labeled item fails immediately:
#   (1) synthetic mini-cases via injected raw_labels/spec_labels (fast, no .sav)
#   (2) git-checkout of the pre-fix political_attitudes.yml (ebe4f00^) — Check A
#       MUST flag system_deserves_support as `error`, and the current spec as `ok`.
#
# Run:  Rscript src/r/audit/test_label_reconciliation.R
# Exit: 0 if all pass, 1 otherwise.

suppressPackageStartupMessages({ library(here); library(yaml) })
source(here::here("src", "r", "audit", "04_label_reconciliation.R"))

.pass <- 0L; .fail <- 0L
ok <- function(cond, msg) {
  if (isTRUE(cond)) { .pass <<- .pass + 1L; cat(sprintf("  PASS  %s\n", msg)) }
  else              { .fail <<- .fail + 1L; cat(sprintf("  FAIL  %s\n", msg)) }
}

# Helpers to build inputs in the haven/spec shapes.
raw_lab <- function(...) { v <- c(...); v }                 # names=text, value=code
spec_lab <- function(...) as.list(c(...))                   # names="1".., value=text
REG <- load_registry_index()
fe  <- function(fn) REG[[fn]]                               # real registry rows

cat("=== Synthetic unit cases ===\n")

# (1) THE BUG: non-reversing fn, raw agree@low, labels agree@high -> error.
r1 <- reconcile_one("t","bug_var","w1","q1","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r1$status=="error" && r1$reason=="opposite_labels",
   "non-reversing fn on inverse-labeled item -> error (system_deserves_support class)")

# (2) CORRECT reversal: reversing fn, raw agree@low, labels agree@high -> ok.
r2 <- reconcile_one("t","good_rev","w1","q2","safe_reverse_4pt", fe("safe_reverse_4pt"),
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r2$status=="ok", "correctly reversed item -> ok (system_capable class)")

# (3) CORRECT identity: non-reversing fn, raw and labels both agree@high -> ok.
r3 <- reconcile_one("t","good_id","w1","q3","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly disagree"=1,"Somewhat disagree"=2,"Somewhat agree"=3,"Strongly agree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r3$status=="ok", "correctly non-reversed item -> ok")

# (4) WRONG reversal: reversing fn, raw agree@high already matches labels -> error.
r4 <- reconcile_one("t","over_rev","w1","q4","safe_reverse_4pt", fe("safe_reverse_4pt"),
  raw_labels  = raw_lab("Strongly disagree"=1,"Somewhat disagree"=2,"Somewhat agree"=3,"Strongly agree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"))
ok(r4$status=="error" && r4$reason=="opposite_labels",
   "reversal applied when raw already matches labels -> error (demo_political_equality class)")

# (5) Unknown fn -> skip.
r5 <- reconcile_one("t","unk","w1","q5","made_up_fn", REG[["made_up_fn"]],
  raw_labels = raw_lab("Strongly agree"=1,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","4"="Strongly agree"))
ok(r5$status=="skip" && r5$reason=="unknown_fn", "unknown fn -> skip/unknown_fn")

# (6) Nominal -> skip.
r6 <- reconcile_one("t","nom","w1","q6","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels = raw_lab("Strongly agree"=1,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","4"="Strongly agree"), var_type="nominal")
ok(r6$status=="skip" && r6$reason=="nominal_no_polarity", "nominal -> skip/nominal_no_polarity")

cat("\n=== Phase 4: Korean lexicon ===\n")
ok(classify_pole("매우 그렇다") == "pos",           "KO: 매우 그렇다 -> pos")
ok(classify_pole("전혀 그렇지 않다") == "neg",       "KO: 전혀 그렇지 않다 -> neg")
ok(classify_pole("매우 만족한다") == "pos",          "KO: 매우 만족한다 -> pos")
ok(classify_pole("매우 불만족한다") == "neg",        "KO: 불만족 disjoint from 만족 -> neg")
ok(classify_pole("동의한다") == "pos",               "KO: 동의한다 -> pos")
ok(classify_pole("동의하지 않는다") == "neg",        "KO: 동의하지 않는다 -> neg")
ok(classify_pole("보통이다") == "unknown",           "KO: midpoint 보통이다 -> unknown")
ok(classify_pole("모르겠다") == "missing",           "KO: 모르겠다 -> missing")
ok(classify_pole("신뢰하지 않는 편이다") == "neg",   "KO: 신뢰하지 않는 편이다 -> neg")
ok(classify_pole("매우 신뢰한다") == "pos",          "KO: 매우 신뢰한다 -> pos")
ok(classify_pole("neither agree nor disagree") == "unknown",
   "EN midpoint still unknown (pos&neg contradiction rule intact)")
ok(classify_pole("매우 노력한다") == "pos",          "KO tier-2: 매우 노력한다 -> pos (generic affirmative)")
ok(classify_pole("전혀 노력하지 않는다") == "neg",   "KO tier-2: 전혀 노력하지 않는다 -> neg (generic negation)")
ok(classify_pole("매우 잘 작동됨") == "pos",         "KO tier-2: 잘 작동됨 -> pos")
ok(classify_pole("전혀 작동되지 않음") == "neg",     "KO tier-2: 작동되지 않음 -> neg")
ok(classify_pole("매우 불만족한다") == "neg",        "KO tier precedence: 불만족한다 stays neg (specific family wins over 한다$)")
ok(classify_pole("Hardly any confidence") == "neg",  "EN: hardly any confidence -> neg (KGSS conf_*)")
ok(classify_pole("Very strong") == "pos",            "EN: very strong -> pos (strength family)")
ok(classify_pole("Very weak") == "neg",              "EN: very weak -> neg")
ok(classify_pole("Strongly disagree") == "neg",
   "strength family does not fire on 'strongly' (agree battery intact)")
ok(classify_pole("매우 위협을 느낀다") == "pos",     "KO tier-2: 위협을 느낀다 -> pos (generic 다$ affirmative)")
ok(classify_pole("별로 위협을 느끼지 않는다") == "neg", "KO tier-2: 느끼지 않는다 -> neg (negation decisive)")
ok(classify_pole("그저 그렇다") == "unknown",        "KO midpoint 그저 그렇다 -> unknown (so-so guard)")
ok(classify_pole("less serious than last year") == "unknown",
   "comparative 'less serious' does not anchor the serious family")
ok(classify_pole("Not very essential") == "neg",     "essential family: 'not very essential' -> neg")

# Missing-code masking: a 0=없다 response code classifies neg lexically and
# sits below the positive pole — unmasked it forces poles_overlap. With the
# spec's missing codes masked (as the engine masks the values), raw anchors.
r_mc <- reconcile_one("t","mc_var","w1","q12","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("매우 필요 하다"=1,"약간 필요 하다"=2,"별로 필요 하지 않다"=3,"전혀 필요 하지 않다"=4,"없다"=0),
  spec_labels = spec_lab("1"="Very necessary","4"="Not necessary at all"),
  missing_codes = c(0, 9))
ok(identical(r_mc$raw_pos_end, "low"),
   "spec missing codes masked from raw labels before pole detection")
r_mc2 <- reconcile_one("t","mc_var2","w1","q12","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("매우 필요 하다"=1,"약간 필요 하다"=2,"별로 필요 하지 않다"=3,"전혀 필요 하지 않다"=4,"없다"=0),
  spec_labels = spec_lab("1"="Very necessary","4"="Not necessary at all"))
ok(grepl("poles_overlap", r_mc2$reason),
   "same labels unmasked -> poles_overlap (masking is what fixes it)")

# Cross-language reconcile: KO raw labels, EN declared labels — the KIPA shape.
r_ko <- reconcile_one("t","ko_bug","w1","q7","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("매우 그렇다"=1,"그런 편이다"=2,"그렇지 않은 편이다"=3,"전혀 그렇지 않다"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Disagree","3"="Agree","4"="Strongly agree"))
ok(r_ko$status=="error" && r_ko$label_locale=="ko",
   "KO raw @low + non-reversing fn + EN declared @high -> error, locale=ko")

cat("\n=== Phase 4: verbatim response_scale fallback (declared side) ===\n")
ps <- .parse_response_scale("1=Strongly agree, 2=Somewhat agree, 3=Somewhat disagree, 4=Strongly disagree")
ok(length(ps) == 4 && ps[["Strongly agree"]] == 1, "response_scale parses to named-numeric")
ok(is.null(.parse_response_scale("open-ended verbatim response")),
   "unparseable response_scale -> NULL (no false anchor)")

# ps declares agree@LOW; raw agree@LOW; non-reversing fn keeps low -> consistent.
r_vb <- reconcile_one("t","vb_ok","w1","q8","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = NULL, verbatim_labels = ps)
ok(r_vb$status=="ok" && r_vb$declared_source=="verbatim_response_scale",
   "no scale.labels -> verbatim fallback anchors declared side (consistent -> ok)")

# Verbatim declares agree@HIGH; raw agree@LOW; non-reversing fn -> contradiction.
ps_rev <- .parse_response_scale("1=Strongly disagree, 2=Somewhat disagree, 3=Somewhat agree, 4=Strongly agree")
r_vb2 <- reconcile_one("t","vb_bug","w1","q8b","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = NULL, verbatim_labels = ps_rev)
ok(r_vb2$status=="error" && r_vb2$declared_source=="verbatim_response_scale",
   "verbatim-declared direction contradicted -> error via fallback")

# scale.labels present -> fallback must NOT override them.
r_vb3 <- reconcile_one("t","vb_prec","w1","q8c","safe_4pt_none", fe("safe_4pt_none"),
  raw_labels  = raw_lab("Strongly agree"=1,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly agree","4"="Strongly disagree"),
  verbatim_labels = ps_rev)
ok(r_vb3$status=="ok" && r_vb3$declared_source=="scale_labels",
   "spec scale.labels take precedence over verbatim fallback")

cat("\n=== Phase 4: method:recode mapping ===\n")
map_rev <- list("1"=4,"2"=3,"3"=2,"4"=1)
r_rec1 <- reconcile_one("t","rec_ok","w1","q9","recode", NULL,
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"),
  recode_map = map_rev)
ok(r_rec1$status=="ok", "reversing mapping matches declared labels -> ok")

map_id <- list("1"=1,"2"=2,"3"=3,"4"=4)
r_rec2 <- reconcile_one("t","rec_bug","w1","q10","recode", NULL,
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","2"="Somewhat disagree","3"="Somewhat agree","4"="Strongly agree"),
  recode_map = map_id)
ok(r_rec2$status=="error" && r_rec2$reason=="opposite_labels",
   "identity mapping on inverse-labeled item -> error")

map_na <- list("1"=NULL,"2"=NULL,"3"=2,"4"=1)
r_rec3 <- reconcile_one("t","rec_na","w1","q11","recode", NULL,
  raw_labels  = raw_lab("Strongly agree"=1,"Somewhat agree"=2,"Somewhat disagree"=3,"Strongly disagree"=4),
  spec_labels = spec_lab("1"="Strongly disagree","4"="Strongly agree"),
  recode_map = map_na)
ok(r_rec3$status=="skip" && r_rec3$reason=="recode_poles_unmapped",
   "mapping that NAs an entire pole -> skip/recode_poles_unmapped")

cat("\n=== Git-based regression: pre-fix vs current political_attitudes.yml ===\n")
spec_rel <- "src/config/abs/harmonize_validated/political_attitudes.yml"
prefix_path <- tempfile(fileext = ".yml")
gx <- suppressWarnings(system2("git", c("show", paste0("ebe4f00^:", spec_rel)),
                               stdout = prefix_path, stderr = FALSE))
have_prefix <- file.exists(prefix_path) && file.info(prefix_path)$size > 0

if (have_prefix) {
  pre <- compute_label_reconciliation("abs", spec_files = prefix_path)
  sds_pre <- pre[pre$variable == "system_deserves_support", , drop = FALSE]
  ok(nrow(sds_pre) > 0 && any(sds_pre$status == "error"),
     "pre-fix (ebe4f00^) system_deserves_support -> error")
} else {
  cat("  SKIP  could not retrieve ebe4f00^ spec (commit missing?)\n")
}

cur <- compute_label_reconciliation("abs",
  spec_files = here::here(spec_rel))
sds_cur <- cur[cur$variable == "system_deserves_support", , drop = FALSE]
ok(nrow(sds_cur) > 0 && !any(sds_cur$status == "error") && any(sds_cur$status == "ok"),
   "current system_deserves_support -> no error, >=1 ok (fix holds; W6 raw labels absent -> skip)")

cat(sprintf("\n=== %d passed, %d failed ===\n", .pass, .fail))
if (.fail > 0L) quit(status = 1L) else quit(status = 0L)
