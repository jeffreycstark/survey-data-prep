# Fault-injection tests against the harmonization engine itself.
# Each test states a hypothesis, applies an adversarial input, and prints verdict.
suppressPackageStartupMessages({ library(here); library(dplyr) })
source(here::here("src/r/harmonize/harmonize.R"))
source(here::here("src/r/utils/recoding.R"))

conv <- list(treat_as_na = c(-1, 7, 8, 9, 97, 98, 99))
mkspec <- function(method, fn = NULL, mapping = NULL, vr = c(1, 4)) {
  h <- if (method == "identity") list(default = list(method = "identity"))
       else if (method == "recode") list(default = list(method = "recode", mapping = mapping))
       else list(default = list(method = "r_function", fn = fn))
  list(id = "testvar", source = list(w1 = "q1"),
       missing = list(use_convention = "treat_as_na"),
       harmonize = h, qc = list(valid_range = vr))
}
oob <- function() { e <- new.env(); e$records <- list(); e }

cat("==== T1: does a stray code 5 on a 4pt item reach the OOB LOG? ====\n")
cat("  (the freedom_vs_equality class: a deleted substantive category)\n")
d <- data.frame(q1 = c(1, 2, 3, 4, 5, 5, 5))   # three 5s = a real response category

log1 <- oob()
r <- harmonize_variable(mkspec("identity"), list(w1 = d), conv, oob_log = log1)
cat(sprintf("  identity      : logged=%d events | output NAs=%d\n",
            length(log1$records), sum(is.na(r$w1))))

log2 <- oob()
r <- suppressWarnings(harmonize_variable(mkspec("r_function", fn = "safe_4pt_none"),
                                         list(w1 = d), conv, oob_log = log2))
cat(sprintf("  safe_4pt_none : logged=%d events | output NAs=%d\n",
            length(log2$records), sum(is.na(r$w1))))

log3 <- oob()
r <- harmonize_variable(mkspec("recode", mapping = list(`1`=1, `2`=2, `3`=3, `4`=4)),
                        list(w1 = d), conv, oob_log = log3)
cat(sprintf("  method:recode : logged=%d events | output NAs=%d\n",
            length(log3$records), sum(is.na(r$w1))))
cat("  => if identity logs but the others do not, Check E is structurally blind\n")
cat("     to every r_function and recode variable.\n\n")

cat("==== T2: reversal fn on a WIDER scale (safe_reverse_4pt on 5pt raw) ====\n")
d5 <- data.frame(q1 = c(1, 2, 3, 4, 5))
log4 <- oob()
r <- harmonize_variable(mkspec("r_function", fn = "safe_reverse_4pt"),
                        list(w1 = d5), conv, oob_log = log4)
cat(sprintf("  output: %s | logged=%d\n", paste(r$w1, collapse = ","), length(log4$records)))
cat("  => raw 5 (a substantive category) vanished:",
    ifelse(is.na(r$w1[5]) && length(log4$records) == 0, "YES, silently", "no"), "\n\n")

cat("==== T3: reversal fn on a NARROWER scale (safe_reverse_5pt on 4pt raw) ====\n")
d4 <- data.frame(q1 = c(1, 2, 3, 4))
r <- harmonize_variable(mkspec("r_function", fn = "safe_reverse_5pt", vr = c(1, 5)),
                        list(w1 = d4), conv)
cat(sprintf("  output: %s\n", paste(r$w1, collapse = ",")))
cat("  => bottom bin unreachable (gov_leaders_abuse_power class):",
    ifelse(min(r$w1) == 2, "YES — shifts, does not error", "no"), "\n\n")

cat("==== T4: fn's own default missing_codes delete codes the SPEC never declared ====\n")
# spec convention treats only 7,8,9,97,98,99 as missing; the fn default also nukes 0
conv0 <- list(treat_as_na = c(7, 8, 9))
d0 <- data.frame(q1 = c(0, 1, 2, 3, 4))   # 0 is substantive on this hypothetical item
r <- harmonize_variable(mkspec("r_function", fn = "safe_4pt_none", vr = c(0, 4)),
                        list(w1 = d0), conv0)
cat(sprintf("  spec declares missing={7,8,9}; raw 0 present; output: %s\n",
            paste(r$w1, collapse = ",")))
cat("  => fn default missing_codes deleted the 0:",
    ifelse(is.na(r$w1[1]), "YES — spec declaration is not what governs", "no"), "\n\n")

cat("==== T5: identity + character column + valid_range: lexicographic comparison? ====\n")
dc <- data.frame(q1 = c("10", "2", "9", "100"), stringsAsFactors = FALSE)
log5 <- oob()
r <- tryCatch(harmonize_variable(mkspec("identity", vr = c(1, 50)),
                                 list(w1 = dc), conv, oob_log = log5),
              error = function(e) paste("ERROR:", conditionMessage(e)))
if (is.character(r)) cat("  ", r, "\n") else {
  cat(sprintf("  output: %s | logged=%d\n", paste(r$w1, collapse = ","), length(log5$records)))
}
cat("\n")

cat("==== T6: .validate_semantic_label on a labels-but-no-label column (W6 shape pre-fix) ====\n")
x <- c(1, 2, 3, 4)
attr(x, "labels") <- setNames(1:4, c("A", "B", "C", "D"))   # value labels, NO question text
dl <- data.frame(q1 = I(x)); dl$q1 <- x; attr(dl$q1, "labels") <- setNames(1:4, c("A","B","C","D"))
r <- tryCatch(safe_4pt_none(dl$q1, data = dl, var_name = "q1", validate_all = list("trust")),
              error = function(e) paste("ERROR:", conditionMessage(e)))
cat("  validate_all with labels-but-no-label:", if (is.character(r)) r else "no error", "\n\n")

cat("==== T7: crashed variable vanishes from harmonize_all with only a warning? ====\n")
spec_all <- list(missing_conventions = conv,
  variables = list(
    good = mkspec("identity"),
    bad  = modifyList(mkspec("identity"), list(missing = list(use_convention = NULL)))))
spec_all$variables$good$id <- "good"; spec_all$variables$bad$id <- "bad"
res <- withCallingHandlers(
  harmonize_all(spec_all, list(w1 = d), silent = TRUE),
  warning = function(w) invokeRestart("muffleWarning"))
cat(sprintf("  variables in: 2 | variables out: %d (%s)\n",
            length(res), paste(names(res), collapse = ", ")))
cat("  => a crashing spec makes its variable silently absent:",
    ifelse(length(res) == 1, "YES", "no"), "\n")
