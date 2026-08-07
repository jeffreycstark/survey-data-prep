# Party-lineage helper — implementation plan

**Status:** Planning. To be implemented next session.
**Drafted:** 2026-05-14.
**Decision context:** Resolves the cross-wave party harmonization decision recorded in `~/.claude/projects/.../memory/project_party_harmonization_decision.md`. Selected option A2 ("helper utility, no engine wiring") after surveying existing infrastructure.

---

## Status snapshot — what already exists

The cross-wave party-name continuity infrastructure is **mostly built**, just not surfaced as a tool:

| Artifact | Path | Status |
|---|---|---|
| Crosswalk lookup table | `data/processed/party_id_crosswalk.csv` (+ `.rds`) | 97 rows: Korea / Taiwan / Thailand × W2-W6. Columns: `country`, `code`, `wave`, `party_name`, `party_lineage`, `coalition`. |
| Build script | `data/processed/create_party_crosswalk.R` | 161-line tribble. Run to regenerate the CSV/RDS. |
| Documentation | `data/processed/party_id_crosswalk.md` | Per-country tables of code → party name across waves. |
| Pre-joined per-respondent file | `data/processed/party_winner_loser.csv` (17,631 rows) | Joins crosswalk to ABS partisanship raw + adds electoral context (winner/loser, winning_coalition). Already consumed by paper 92b. |
| ABS partisanship YAML | `src/config/abs/harmonize/partisanship.yml` | Only abstracts `has_party_id` (binary) and `party_closeness` (ordinal). Deliberately avoids party identity. |
| KGSS political_behavior YAML | `src/config/kgss/harmonize/political_behavior.yml` | Stores raw per-wave codes (`party_id`, `party_pref`), documents "NOT comparable across waves". |
| KINU politics YAML | `src/config/kinu/harmonize/politics.yml` | No wave-comparable party_id — only `party_warmth_justice` (Justice Party feeling thermometer). |

**How fragmentation is handled in the existing crosswalk:** keyed on `(country × code × wave)`, not `(country × code)`. Same code can map to different parties across waves — e.g., Korea code 301 = Uri Party in W2/W3, Saenuri in W4, Democratic Party of Korea in W5. The `party_lineage` column tracks ancestral identity ("Uri/Democratic lineage" vs "Grand National/Saenuri lineage") and `coalition` tracks camp ("progressive" / "conservative"). This is the correct factoring — code is just a slot, lineage is the political descent, coalition is the analytic label.

**The remaining gap:** every paper that wants cross-wave camps duplicates the join logic. Paper 92b does it manually in `31_party_fe_robustness.R`. There is no shared helper.

---

## Recommended path — A2 ("helper utility, no engine wiring")

Build one R helper function that papers can `source()` and call to add `party_lineage` + `coalition` columns to any dataframe with `(country, wave, code)` columns. The harmonization engine stays unchanged. The crosswalk CSV stays in its current location.

### Why not A1 (engine-baked)
- **Coalition labels are contested.** "BAREUNMARAE = conservative" or "centrist"? "Bhumjaithai = pro-Thaksin" or "other"? Baking them into the harmonized `.rds` forces every paper to disagree-and-override rather than choose-at-load.
- **Crosswalk is partial (3 of 12 ABS countries).** Engine wiring would mean adding NA columns for 9 countries × 6 waves, surfacing the gap as a permanent reminder that the crosswalk is incomplete.
- **Reversible.** If a critical paper later needs engine-baked versions, A1 can be implemented on top of A2 — just point a `derive` method at the same CSV.

### Why not C (status quo)
- Paper 92b manually does the join; future Korea/Taiwan/Thailand papers will repeat the boilerplate.
- The crosswalk is unannounced — newcomers to the repo won't know it exists.

---

## Proposed helper signature

```r
#' Join cross-wave party lineage + coalition labels.
#'
#' @param df          Data frame with at least country, wave, and party-code
#'                    columns. ABS papers typically have `country` (integer or
#'                    name), `wave` ("w1"/"w2"/... or 1/2/...), and a per-wave
#'                    party-code variable.
#' @param country_col Name of the country column in df. Accepts integer codes
#'                    (1=Japan, 2=HK, 3=Korea, 7=Taiwan, 8=Thailand, ...) OR
#'                    character names ("Korea", "Taiwan", "Thailand"); resolved
#'                    internally.
#' @param wave_col    Name of the wave column. Accepts "w2"/"W2"/2.
#' @param code_col    Name of the per-wave party-code column (the raw question
#'                    response — e.g. q47 in W3, q53 in W4).
#' @param crosswalk_path  Path to the crosswalk RDS/CSV. Defaults to
#'                        here("data/processed/party_id_crosswalk.rds").
#' @param columns     Which crosswalk columns to attach. Default
#'                    c("party_lineage", "coalition"). Use "party_name" to
#'                    also get the wave-specific party name.
#' @param suffix      Append this suffix to added column names (e.g. "_camp").
#'                    NULL → no suffix; conflicts error out.
#'
#' @return df with the requested columns appended.
#'
#' @details
#' Rows where (country, code, wave) is not in the crosswalk get NA. The
#' function warns ONCE per (country, wave) combination that is fully absent
#' from the crosswalk — useful for surfacing "this country isn't covered yet"
#' rather than silently producing all-NA columns.
join_party_crosswalk <- function(df,
                                  country_col,
                                  wave_col,
                                  code_col,
                                  crosswalk_path = NULL,
                                  columns = c("party_lineage", "coalition"),
                                  suffix = NULL) {
  # implementation...
}
```

### Internal logic (sketch)

1. Load crosswalk from `crosswalk_path` (default `here("data/processed/party_id_crosswalk.rds")`).
2. Normalize country: if numeric, map to crosswalk's country names (1→Japan, 2→HK, 3→Korea, 7→Taiwan, 8→Thailand, etc. — use the survey-specific code map from CLAUDE.md / data dictionary).
3. Normalize wave: uppercase, strip "w"/"W" prefix, recompose as "W{n}".
4. Identify (country × wave) combinations in df that are fully absent from the crosswalk. Emit one `warning()` per missing combo with the suggested action: "Country X / Wave Y not in crosswalk. {n_rows} rows will receive NA for {columns}. To extend, edit data/processed/create_party_crosswalk.R."
5. Left-join on (country, wave, code).
6. Apply suffix to added column names if provided. Error if conflict and no suffix.
7. Return.

### File locations

| File | Path | Rationale |
|---|---|---|
| Helper R script | `src/r/lookups/party_lineage.R` (new dir) | Separates "paper-time" tools from "harmonization-time" tools (`src/r/utils/` is the latter). |
| Usage example | `src/r/lookups/README.md` | Brief: when to use this, edge cases, link to crosswalk doc. |
| Crosswalk CSV / RDS | **Keep at `data/processed/`** | Already consumed by 92b. Don't move — would break that paper. Suggest moving to `data/lookups/` only if/when a wider reorganization happens. |

### Edge cases the helper must handle

1. **(country, wave) not in crosswalk** (e.g., Cambodia W6): all rows get NA, warning fires once.
2. **(country, code, wave) miss within a covered (country, wave)**: NA, no warning (legitimate "Other" / minor-party respondents).
3. **Column name conflict** (df already has `coalition`): error unless `suffix` is provided.
4. **Wave format mismatch** (df uses "w2", crosswalk uses "W2"): normalize internally.
5. **Country format mismatch** (df has integer 3, crosswalk has "Korea"): support both via internal map.
6. **Multiple party-code columns** (e.g., a paper analyzing both `party_id` and `party_pref`): call the helper twice with different `code_col` and `suffix` values.
7. **R10 / future waves not in crosswalk**: same as case 1 — NA + warn.

---

## Open questions for tomorrow

Before implementing, decide:

1. **Country-code mapping table.** The helper needs to map ABS integer country codes (1=Japan, 2=HK, ...) to the names used in the crosswalk ("Taiwan", "Korea", "Thailand"). Should this map live:
   - (a) Hardcoded inside `party_lineage.R`?
   - (b) In a separate `data/lookups/abs_country_codes.csv`?
   - (c) Pulled from an existing source (the regime crosswalk has its own country mapping)?

   *Recommendation:* (b) — externalize so the helper doesn't need to be updated when wave 7 adds a country.

2. **What to do when warning fires.** The function warns about missing (country × wave) combos. Three options:
   - Warning + return NA (current proposal).
   - Error and refuse to return.
   - Silent NA (no warning).

   *Recommendation:* warning. Errors are too aggressive for exploratory work; silent NA is the bug we're trying to fix.

3. **Should `winning_coalition` / `is_winner` (from `party_winner_loser.csv`) be exposed too?**
   - These add electoral context: did this respondent's chosen party win the most recent election?
   - Building a wider helper that exposes them is straightforward, but it requires loading the per-respondent file (17,631 rows) and is ABS-specific.

   *Recommendation:* defer to a second helper, `join_electoral_context()`. Keep `join_party_crosswalk()` general and lean.

4. **Tests.** Write tests against the existing pre-joined `party_winner_loser.csv` — the helper applied to ABS partisanship data should produce columns identical to the equivalent columns in that file. Useful as a regression check.

   *Recommendation:* yes, write the test. Put it at `tests/r/test_party_lineage.R` (if the repo has a tests/ convention) or `src/r/lookups/test_party_lineage.R`.

5. **Should this be documented in CLAUDE.md?** Currently the crosswalk isn't mentioned anywhere. Adding a section in `CLAUDE.md` under "Cross-survey scale gotchas" or a new "Lookups" section would surface it for future agents and humans.

   *Recommendation:* yes — one paragraph in CLAUDE.md + link to `src/r/lookups/README.md`.

---

## Implementation plan (tomorrow)

Estimated total: ~45 minutes.

1. **(5 min)** Create directory `src/r/lookups/`. Move (or don't — keep at `data/processed/`) the crosswalk CSV.
2. **(5 min)** Build the country-code map. Either externalize to `data/lookups/abs_country_codes.csv` or hardcode. (Decision Q1.)
3. **(15 min)** Write `src/r/lookups/party_lineage.R` with `join_party_crosswalk()`. Include:
   - Argument validation (df has required cols, paths exist).
   - Country normalization.
   - Wave normalization.
   - Missing-(country×wave) warning logic.
   - The actual `left_join()` from `dplyr`.
   - Suffix handling.
4. **(10 min)** Write `src/r/lookups/test_party_lineage.R`. Two tests:
   - Apply helper to a synthetic 5-row df → verify Korea code 301 W3 = "Uri/Democratic lineage" / "progressive".
   - Apply helper to ABS W3 partisanship data → verify the output columns match `party_winner_loser.csv` for the rows where wave==W3 (sample 100).
5. **(5 min)** Write `src/r/lookups/README.md` with usage example showing 92b's use case rewritten via the helper.
6. **(5 min)** Add one paragraph to `CLAUDE.md`'s "Cross-survey scale gotchas" section pointing to the lookups dir.

After implementation, optionally:
- **(20 min)** Rewrite paper 92b's manual join in `31_party_fe_robustness.R` to use the helper. Tests would catch any regression.

---

## Out of scope (do not do tomorrow)

1. **Extending the crosswalk to other ABS countries.** Currently only Korea/Taiwan/Thailand covered. Adding Japan, HK, Indonesia, etc. is ~5-10 hours per country pair of codebook work. Track as a separate task.
2. **Wiring the crosswalk into the harmonization engine.** If a future paper needs derived `party_camp` columns directly in `abs_harmonized.rds`, that's option A1 — implement on top of A2 by adding a `derive` method to `partisanship.yml`.
3. **Retroactive paper updates.** Existing papers (only 92b currently) can continue with their manual joins. The helper is opt-in.
4. **KGSS / KINU equivalents.** Korean political parties at the survey-internal level (not the ABS Korea sample) have their own complications. KGSS has 11+ waves with year-specific codes; the crosswalk would need ~70 rows just for Korea alone if extended. Defer.

---

## What this doc resolves

When the user comes back to the cross-wave party harmonization decision (recorded in `project_party_harmonization_decision.md`, dated 2026-05-06), this doc is the answer:

- **Decision:** option A2 (helper utility, no engine wiring).
- **Reason:** the crosswalk + build script + per-respondent join already exist. The remaining work is just a thin helper to surface the existing infrastructure as a reusable tool.
- **Not chosen:** A1 (engine-baked) — coalition labels are contested and the crosswalk is partial; B (camp-only) — loses lineage info; C (status quo) — duplicates manual joins.

The deferred memory can be marked resolved when the helper ships.
