# Audit findings — open for review

Last updated: 2026-05-10

This file records audit findings that need substantive judgment from Jeff. The audit infrastructure surfaces; this file tracks what remains to investigate. Update as items get resolved.

---

## 🔴 High priority — likely real bugs (none currently open)

All previously identified high-priority bugs have been fixed. See "Resolved findings" at bottom for the audit trail.

---

## 🟡 Medium priority — real but minor (review when convenient)

### KINU `cohort` valid_range over-claim
- **Where:** `src/config/kinu/harmonize/demographics.yml`
- **Finding:** YAML claims `valid_range: [1, 7]`. Codebook only contains codes 1-6 across all 13 waves; the 7th cohort ("Z generation") is never observed.
- **Action:** Either narrow to `[1, 6]` (drop the unobserved 7th cohort) or document why the claim anticipates future data. F4 reports 13 valid_range fails (one per wave) for this variable.
- **Surfaced by:** F4 KINU run (commit `d6eb2e9`).

### KINU `home_region` valid_range over-claim
- **Where:** `src/config/kinu/harmonize/demographics.yml`
- **Finding:** YAML claims `valid_range: [1, 19]`. Codebook is `[1, 18]` (1-16 are Korean sido, 17 = North Korea, 18 = foreign). Code 19 never observed.
- **Action:** Narrow to `[1, 18]`. F4 reports 13 valid_range fails (one per wave).
- **Surfaced by:** F4 KINU run (commit `d6eb2e9`).

### IPUS `uni_view` valid_range vs codebook
- **Where:** `src/config/ipus/harmonize/unification.yml`
- **Finding:** YAML claims `valid_range: [1, 4]`. Codebook contains only codes 1-3 in 12 of the 18 waves; code 4 ("should not happen") is empty in source data for those years. Some waves (W2007, etc.) flag code 4 as a missing code.
- **Action:** Either narrow per-wave (`valid_range_by_wave`) or accept that code 4 is theoretically valid but empirically rare. Worth verifying against the IPUS questionnaire whether code 4 actually exists as an option in those years.
- **Surfaced by:** F4 IPUS run.

### AFRO `dem_satisfaction` W2 coverage loss
- **Where:** `src/config/afro/harmonize/democratic_attitudes.yml`
- **Finding:** 1.6% coverage loss (355 / 22,005 values) at W2. Exceeds the 1% error threshold. The recode is dropping intended-valid codes.
- **Action:** Compare raw W2 distribution to harmonized; identify which codes are being NA-coerced.
- **Surfaced by:** E2 first run.

---

## 📋 Residual systematic findings (post-fixes)

These are categories where the audit infrastructure is doing its job but the remaining signal needs a YAML hardening pass.

### ABS missing_codes residue
After the bulk-add of `missing.use_convention` (commit pending), ABS F4 missing_codes fails dropped from 931 → 54. The residual 54 are real cases where:
- Some variable's codebook has missing codes the YAML's chosen convention doesn't cover.
- Or per-variable `missing.codes:` overrides are incomplete.

Worth a one-pass review to either tighten conventions or add per-variable `missing.codes:` entries.

### KINU missing_codes residue
KINU's residual after bulk-add: 1097 → 409. Higher than ABS because KINU questionnaire layout uses 9/99/9999 inconsistently across waves. Each spec's `missing_conventions:` block needs to capture all the codes used. Worth a per-spec review.

### IPUS missing_codes residue
IPUS residual: 61 → 18. Manageable. Likely related to the wave-specific KOSSDA recoding markers (5.5).

### ABS value_labels surface mismatches
~140 fail rows from cosmetic differences:
- "60+" vs "over 60"
- `dem_statement_*` family: YAML uses analytical shorthand ("Statement A/B/C") while codebook stores full statement text
- `cohort` "Millennials" (YAML) vs "Millenials" (codebook typo)

These are not bugs — the YAML's labels are reasonable. Could be silenced by either tightening F4's fuzzy match or accepting the surface noise.

### AFRO `age_cohort` (separate from the false-positive case)
The false-positive Spearman ρ ≈ 0.965 was resolved (commit `b6b315e` added the function to F4's skip list). But: any genuine off-by-one in the bin boundaries would have been hidden by the same cap. Worth a one-time hand verification of the age→cohort mapping at boundary ages (29/30, 39/40, 49/50, 59/60) using a few country/round samples.

---

## ✅ Resolved findings (audit trail)

For the record — items the audit caught and that have been investigated/fixed.

| Date | Variable | Outcome | Commit |
|---|---|---|---|
| 2026-05-09 | ABS W6 builder hazard | Fixed (delegate + guard) | `5e02866` |
| 2026-05-09 | `compute_procedural_index` missing from registry | Added | `34ff235` |
| 2026-05-09 | Duplicate `id: hh_income_sat` across two ABS specs | Removed from `demographics.yml` | `48ac398` |
| 2026-05-09 | `dem_extent_current` "critical citizens" pattern in anchor | Anchor sign demoted to `either` | `27131d1` |
| 2026-05-10 | ABS `hh_income_sat` W5 value-5 leakage + W2 stale output | Function fix + pipeline rerun | `2d8a7e3` |
| 2026-05-10 | ABS W1 fractional dem-rating values | Type changed `ordinal → continuous` (later refined per `dem_extent_current` finding) | `2d8a7e3` |
| 2026-05-10 | AFRO `age_cohort` ρ 0.965 false positive | Added to F4 skip list (5-bin discretization ceiling) | `b6b315e` |
| 2026-05-10 | IPUS `uni_timing` 13-26% coverage loss across 2007-2014 | Raw scale is 6-cat not 5; fixed mapping | `b6b315e` |
| 2026-05-10 | KINU `urban_rural` "directional swap" | F4 false positive (post-harmonization labels vs raw codebook); F4 fixed to skip non-identity methods | `f624cfd` |
| 2026-05-10 | `dem_extent_current` Frankenstein scale (W1 10pt vs W2-W6 4pt) | Verified against W2 codebook + .doc questionnaire; W1=null, type=ordinal, scale 1-4, reverse-coded | `66d1ed8` |

---

## 🛠 Open audit framework work (incomplete tickets — not findings)

These are framework tickets that haven't shipped yet. Each is in `audit/02-implementation-tickets.md` if you want to dispatch a fresh agent.

### Phase B (deferred)
- B5: Make `valid_range` mandatory (no longer warn on missing — error)
- B6: Require `qc.validate.phrase` for `safe_reverse_*` rules
- See memory file: `~/.claude/projects/-Users-jeffreystark-Development-Research-survey-data-prep/memory/project_audit_phase_b_deferred.md`

### Phase D (partial — D1-D4 + D8-D9 done)
- D5: Undeclared-reversal scan (variables with `method: identity` whose anchor correlation is opposite the expected sign)
- D6: Per-country sign-disagreement explicit module (partly subsumed by D3 but a dedicated CLI would help)
- D7: `qc.wave_direction_flip:` schema support (declare wave-specific anchor direction reversals)
- D10: Cross-survey `authoritarianism` anchor (currently only ABS-side via `democratic_attitudes`)

### Phase F Tier 3 (deferred)
- KGSS PDF extraction (Korean cumulative codebook)
- KIPA-corruption PDF extraction (per-year Korean + English)
- LBS PDF extraction (per-year Spanish + English, ~24 years × 2 langs)
- AFRO PDF extraction (R1 + R9 + per-round)
- WVS PDF extraction (7 wave codebooks)
- Arab Barometer PDF extraction
- KAMOS PDF extraction

ABS Tier 2 done (SPSS metadata, 99.6% coverage). Tier 1 (KINU + IPUS xlsx) done. Tier 3 is the long tail.

### Phase H (CI integration)
- H1: Local audit orchestrator (`make audit`)
- H2: GitHub Actions audit workflow with merge gates
- H3: Per-layer gating policy
- H4: Audit-pass certificate generator for tagged releases

---

## How to use this file

When you investigate something here:
1. Move the entry from "open" to "Resolved findings" with the resolving commit hash.
2. If a new finding shows up, add to the appropriate priority bucket.
3. Don't delete entries — preserve the trail.

This file is intentionally NOT in `audit/`; it lives at the repo root so it's visible and harder to forget about.
