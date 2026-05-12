# Audit findings — open for review

Last updated: 2026-05-10

This file records audit findings that need substantive judgment from Jeff. The audit infrastructure surfaces; this file tracks what remains to investigate. Update as items get resolved.

---

## 🔴 High priority — likely real bugs (none currently open)

All previously identified high-priority bugs have been fixed. See "Resolved findings" at bottom for the audit trail.

---

## 🟡 Medium priority — real but minor (review when convenient)

### NEW 2026-05-12: KINU codebook extractor should read from .sav labels, not xlsx
- **Where:** `src/r/audit/extractors/kinu_codebook.R`
- **Finding:** The current KINU extractor reads from `data/kinu/raw/kinu_2014-2024_codebook_en.xlsx`. That xlsx is incomplete relative to the .sav file's value labels — confirmed for `cohort` (xlsx documents only codes 1-6; .sav has code 7 "Z generation" with 290 observations). The .sav labels reflect KINU's actual data coding; the xlsx appears to be a partial documentation snapshot. Other variables may have similar gaps (untested as of 2026-05-12).
- **Action:** Rebuild the KINU extractor to source from `data/kinu/raw/kinu_2014-2023_en.sav` using `haven::read_sav()` and `attr(x, "labels")`, mirroring the pattern in `src/r/audit/extractors/abs_codebook.R`. The xlsx can still be used as a secondary source for question_text (verbatim Korean wording) if .sav variable labels are too terse, but value labels should come from .sav.
- **Decision required:** Should the new extractor PRIMARILY use .sav (recommended — single source of truth for codes/labels), or do a HYBRID merge of .sav + xlsx (more comprehensive but more complex)?
- **Effort:** ~1-2 hours.
- **Surfaced by:** cohort revert during the 2026-05-12 medium-TODO sweep.


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

### IPUS `uni_view` — Frankenstein scale across the 2019 questionnaire restructure
- **Where:** `src/config/ipus/harmonize/unification.yml`
- **Finding:** **Much bigger than the original F4 report suggested.** Investigation showed:
  1. **All 18 years have code 4** (F4's "absent in 12 waves" was wrong).
  2. **2019 introduced a 5-category scheme** by splitting "ASAP at any cost" (old code 1) into two categories ("at any cost" + "ASAP"). Old codes 2/3/4 shifted down to new codes 3/4/5.
  3. The identity-method harmonization silently conflates pre-2019 codes with post-2019 codes (same value, different meaning).
  4. **YAML label 4="Should not happen" is wrong.** Neither codebook scheme has an "opposed" category. The actual label is "통일에 대한 관심이 별로 없다" = "not very interested in unification" (apathy, not opposition).
  5. Post-2019 code 5 is silently NA-coerced by the [1,4] valid_range — same shape as the `uni_timing` bug fixed in `b6b315e`.
- **Decision required:** confirm the 2019 1+2 split is granularity (give the "should happen" group more resolution) vs new category. If granularity (most plausible reading), the proposed collapse below is correct. If new category, a different mapping is needed.
- **Action:** add per-wave recode mappings for 2019-2024:
  ```yaml
  harmonize:
    default:
      method: identity   # 2007-2018: passes through
    exceptions:
      w2019: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
      w2020: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
      w2021: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
      w2022: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
      w2023: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
      w2024: { method: recode, mapping: {1: 1, 2: 1, 3: 2, 4: 3, 5: 4} }
  ```
  Plus fix `scale.labels.4` from "Should not happen" → "Not very interested in unification". Re-run IPUS pipeline + verify F4 + verify the cross-wave drift (G1) for uni_view drops markedly post-fix.
- **Effort:** ~30 min including substantive review of the 1+2 split.
- **Surfaced by:** F4 IPUS run. Investigated commit `3672fea` (see findings doc §Finding 3).

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
| 2026-05-12 | KINU `cohort` apparent over-claim `[1,7]` | Confirmed AGAINST narrowing after investigation. The xlsx codebook documents codes 1-6 only, but the raw .sav has code 7 ("Z generation") with 290 observations across 2014-2023. xlsx is incomplete; the YAML's [1,7] reflects reality. Kept at [1,7] with caveat note. | _this commit_ |

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
