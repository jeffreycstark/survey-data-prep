# Audit findings — open for review

Last updated: 2026-05-10

This file records audit findings that need substantive judgment from Jeff. The audit infrastructure surfaces; this file tracks what remains to investigate. Update as items get resolved.

---

## 🔴 High priority — likely real bugs (none currently open)

All previously identified high-priority bugs have been fixed. See "Resolved findings" at bottom for the audit trail.

---

## 🟡 Medium priority — real but minor (review when convenient)

### ~~NEW 2026-05-12: KINU codebook extractor should read from .sav labels~~ — **RESOLVED 2026-05-12**
- **Resolution:** Rebuilt `src/r/audit/extractors/kinu_codebook.R` to source from `data/kinu/raw/kinu_2014-2023_en.sav` via `haven::read_sav()`, mirroring the ABS pattern. Year column (1-13) maps to wave keys via `.KINU_YEAR_TO_WAVE`. Per (variable × wave) emits rows only where the variable has non-NA observations.
- **Outcome:** Cohort code 7 (Z generation) now captured. F4 valid_range fails for KINU dropped 26 → 0 (cohort + home_region both reconcile cleanly). Rows 17,230 → 16,900; unique variables 912 → 901; missing-code detection slightly more aggressive (.sav exposes more codes than xlsx).
- **Tradeoff documented:** question_text now comes from the .sav variable label (haven attr) which may be terser than the xlsx's full question wording. Accepted for label accuracy.
- **Commit:** `bfd2062`.


> **All 4 medium-priority items investigated 2026-05-11.** Full evidence + recommended fixes in [`audit/findings_medium_2026-05-11.md`](audit/findings_medium_2026-05-11.md). Summary entries below — read the findings doc before editing.

### ~~KINU `cohort` valid_range over-claim~~ — **RESOLVED 2026-05-12 (different reason)**
- **What happened:** Investigation initially concluded code 7 was never observed (xlsx codebook only documents codes 1-6, and the codebook parquet F-KINU extracted matched). On the basis of that conclusion, narrowed `valid_range` from [1,7] to [1,6]. Re-running validation surfaced 12 NEW coverage errors (1-4% loss across waves). Checking the .sav directly revealed **the raw KINU .sav DOES have code 7 ("Z generation") with 290 cases across 2014-2023 (growing from 19 in 2014 to 41 in 2023)**. The xlsx codebook is incomplete relative to the .sav.
- **Resolution:** Reverted to [1, 7]. Added a CODEBOOK CAVEAT comment in the YAML documenting the xlsx-vs-.sav gap.
- **Meta-finding:** The KINU codebook extractor (which reads from xlsx) is incomplete relative to .sav labels. This affects F4 reconciliation quality for KINU. See new "KINU codebook extractor should read from .sav labels" entry below.
- **Commit:** _this commit_ — cohort kept at [1,7] after empirical verification against raw .sav.

### ~~KINU `home_region` valid_range over-claim~~ — **RESOLVED 2026-05-12**
- **What happened:** YAML claimed `valid_range: [1, 19]`. Raw `home` in .sav has only codes 1-18 (1-16 sido, 17=North Korea, 18=Foreign). Code 19 not declared in .sav labels, not observed in data.
- **Resolution:** Narrowed `valid_range` to [1, 18]. Removed `19: "..."` from scale.labels. Updated description.
- **Note:** KINU has TWO region coding schemes — demographics-region (used by `home` raw, 18 codes) and basic-region (used by `region` raw, 19 codes with Sejong=17 and NK=19). The two are NOT parallel despite identical-looking sido codes 1-16.
- **Commit:** _this commit_.

### ~~IPUS `uni_view` — Frankenstein scale across the 2019 questionnaire restructure~~ — **RESOLVED 2026-05-12**
- **What happened:** IPUS restructured response options in 2019, splitting "ASAP at any cost" (pre-2019 code 1) into two separate codes (1 = "at any cost", 2 = "ASAP"), pushing all subsequent codes down by one. The identity-method harmonization silently conflated the two schemes. Plus the YAML's `scale.labels.4 = "Should not happen"` was fabricated — no "opposed to unification" category exists in either scheme; the actual label is "not very interested in unification" (apathy).
- **Resolution:** Per-wave recode mappings for w2019-w2024 collapse codes 1+2 → harmonized 1 (treating the 2019 split as granularity within the "should happen" group rather than a new conceptual category) and shift 3→2, 4→3, 5→4. Pre-2019 waves (w2007-w2018) keep identity method. YAML labels corrected. Audit impact: IPUS L3 errors dropped 7 → 1 (the remaining 1 is `urban_rural w2008`, unrelated).
- **Substantive caveat documented in YAML:** the 1+2 collapse loses the post-2019 finer-grained distinction between "at any cost" and "ASAP". Researchers who need that distinction should consume raw `uni02_01` directly. Distribution sanity-check confirmed n_4 ("not very interested") is now properly preserved at 69-132 cases per wave post-2019 (previously silently NA-coerced by valid_range [1,4]).
- **Commit:** _this commit_.

### ~~AFRO `dem_satisfaction` W2 coverage loss~~ — **RESOLVED 2026-05-12**
- **Resolution:** Split off "Country is not a democracy" responses into a sister variable `dem_country_not_democracy` (binary) rather than just declaring them as missing. Preserves the substantive signal instead of hiding it.
- **What changed:**
  - New binary variable `dem_country_not_democracy` covers R1-R9 (R10 pending YAML mapping). Captures 4,898 respondents across all rounds who said their country is not a democracy (R1=436, R2=355, R3=391, R4=407, R5=965, R6=1054, R7=839, R8=849, R9=932). The R9 932-case group was a particularly important catch — previously silently NA-coerced by the engine's valid_range [1,4] under identity harmonization.
  - `dem_satisfaction` now declares `coverage_missing_codes_by_wave: [0]` for w2-w9, making the intent visible to the audit.
- **Audit impact:** AFRO L3 errors dropped 53 → 45. The 8 dem_satisfaction coverage errors are gone; new variable validates clean.
- **Commit:** (pending) — same commit that lands this update.

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
| 2026-05-12 | AFRO `dem_satisfaction` "Country is not a democracy" responders silently dropped | Split into sister binary `dem_country_not_democracy` (R1-R9); 4,898 cases across rounds now captured instead of NA-coerced. R9's 932 cases were also being silently dropped under identity+range-coerce. | `dda1b22` |
| 2026-05-12 | KINU `home_region` over-claim `[1,19]` | Narrowed to `[1,18]` (raw `home` only has 18 codes — 17=NK, 18=Foreign). KINU has TWO region coding schemes; `home` and `region` are NOT parallel despite identical 1-16 codes. | _this commit_ |
| 2026-05-12 | KINU `cohort` apparent over-claim `[1,7]` | Confirmed AGAINST narrowing after investigation. The xlsx codebook documents codes 1-6 only, but the raw .sav has code 7 ("Z generation") with 290 observations across 2014-2023. xlsx is incomplete; the YAML's [1,7] reflects reality. Kept at [1,7] with caveat note. | `7021664` |
| 2026-05-12 | IPUS `uni_view` Frankenstein scale (2019 questionnaire restructure conflated with pre-2019) | Per-wave recode for 2019-2024 collapses post-2019 codes 1+2 → harmonized 1, shifts 3→2, 4→3, 5→4. Fixes wrong YAML label "Should not happen" (actual label = "not very interested in unification"). Preserves the post-2019 "not interested" group previously silently NA-coerced by valid_range [1,4]. IPUS L3 errors: 7 → 1. | `6b72f17` |
| 2026-05-12 | KINU codebook extractor incomplete vs .sav labels | Rebuilt from xlsx to .sav source (haven::read_sav). Captures cohort code 7 ("Z generation") and other previously-omitted codes. F4 valid_range fails for KINU: 26 → 0. | `bfd2062` |

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
