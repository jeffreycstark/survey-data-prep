# Row identifiers for every harmonized survey — design

**Date:** 2026-08-10 · **Status:** approved by Jeff (design); implementation pending
**Trigger:** the ABS `idnumber` bug (research-vault, 2026-08-09) — missing-code
conventions deleted 357 real respondent IDs, and the repair revealed that no
harmonized survey file carries a unique row identifier at all.

## Problem

The shared engine mints a per-wave `row_id` that all twelve 99-scripts then
drop. Nine surveys ship no identifier of any kind; ABS keeps a per-wave
positional `row_id` plus an `idnumber` that is not a key; only the panels
(CFPS, KLoSA) have trustworthy native keys. Nothing asserts uniqueness
anywhere, so ID damage is invisible by construction (the
"wrong-but-consistent" class in docs/QA.md).

## Decisions (Jeff, 2026-08-10)

1. **IDs must be stable across pipeline rebuilds**, so papers can durably
   reference, exclude, and re-find rows.
2. **Native-key anomalies are kept and documented, never dropped.** No
   respondent row is deleted; known release-file duplicates become reasoned
   exemptions.
3. Native keys were empirically tested (2026-08-10) and **cannot be the
   backbone** — verdict table below.

## Native-key evidence (measured, not assumed)

| survey | best native key | verdict |
|---|---|---|
| kgss | `YRRESPID` | unique file-wide (23,282) |
| kinu | `year+id` | unique (13,030) |
| ipus | `year+id` | unique, all 18 years |
| cfps / klosa | `wave+pid` | unique |
| lbs | `year+idenpa+numentre` | clean 1997+; **no ID vars 1995/96**; 2004 has 2,491 NA `numentre` |
| afro | `round+country+respno` | clean except **R8: 24 dups**; R1 lacks `respno` |
| abs | `country+wave+idnumber` | **2 HK W5 duplicate pairs** (in ABS's release; `704273201`, `704273901`) |
| arab-barometer | `wave+country+id` | W5: 3 dups; **W8: 2,400 rows with ID=0**; W1–W4: no ID |
| kamos | `file+id` | 1 dup (KAMOS_1-2 2016 file) |
| kipa_corruption | `year+id` | clean except **2019: 74 dups**; no `id` 2013–2015 |
| wvs | `country+S007` | W1/W2/W5 clean; **W3: 4,005 dups**; W4/W6 lack S007 |

## Design

### §1 row_uid (engine change)

- Minted in `stack_harmonized_wide()` (`src/r/data_prep_modules/2_harmonize_all.R`)
  for every survey identically: `"<survey>.<wave>.<%06d position>"`, e.g.
  `abs.w5.001234`, `kgss.w2008.000412`. Position = row order within the loaded
  wave. Character column.
- **New column name** (`row_uid`), not a reuse of `row_id`: ABS's shipped
  `row_id` has different semantics and silent meaning-change is the bug class
  this repo fights. The engine stops emitting `row_id`; the eleven
  `select(-row_id)` lines are removed, and ABS's 99-script (the one survey
  that kept `row_id`) switches to the new column; stale references break
  loudly.
- `run_survey_harmonization()` passes the survey key through to the minting
  site (it already knows it).
- **Stability contract (documented, not assumed):** row_uid is stable across
  rebuilds while that wave's raw file and loader are unchanged. Run manifests
  already hash raw inputs, so any event that could renumber is detectable via
  the freshness layer. Renumbering is scoped to the changed wave only.
- Deterministic-loader caveats verified: CFPS person-wave age filter and the
  KGSS/KIPA cumulative-file splits are deterministic, so positions are too.

### §2 native IDs as data columns (spec layer)

Purpose: tracing rows back to raw files and legitimate merges — never
uniqueness. Additions (all `type: nominal`, skip range/unmapped checks, and a
**no-missing-codes convention** — the generalized lesson of the idnumber bug;
an ID variable never points at `treat_as_na`):

| survey | new spec id | source | waves |
|---|---|---|---|
| kgss | `respid` | `RESPID` | all (YEAR already harmonized) |
| afro | `respno` | `RESPNO`/`respno` | R2–R10 (R1 null) |
| lbs | `numentre` | `numentre`/`NUMENTRE` | 1997+ (1995/96 null) |
| wvs | `s007` | `S007` | w1, w2, w5 only. w3 deliberately null — its 4,005 dups make it join-hazardous; w4/w6 null, absent in raw |
| arab-barometer | `native_id` | `id`/`ID` | w5, w7, w8 (w1–w4 null) |
| kamos | `native_id` | `id` | all wave files |
| kinu | `native_id` | `id` | all |
| ipus | `native_id` | `id`/`ID` | all |
| kipa_corruption | `native_id` | `id` | all except 2013–2015 (null) |

Values are kept verbatim — AB W8's 2,400 zeros stay zeros (documented
sentinel, exempted in §3). Existing `idnumber` (abs), `pid` (cfps/klosa),
`respondent_id` (gcb spec) are unchanged.

### §3 uniqueness guard

- **Build-time hard assert** in every 99-script: `row_uid` present, character,
  zero NA, zero duplicates — a broken backbone stops the build.
- **Audit module** `src/r/audit/check_key_uniqueness.R`, wired into
  `run_all.R` (data-dependent → local audit, not CI):
  - reads `src/config/_audit/key_declarations.yml` (per survey: native key
    columns + scope, incl. panels' `wave+pid` and dormant gcb);
  - asserts declared native keys unique after applying
    `src/config/_audit/key_uniqueness_exemptions.yml` (the six known
    anomalies above, each with a reason); unexempted violations are errors;
  - reports to `audit/reports/key_uniqueness.csv`.
- Fault-injection tests `src/r/audit/test_key_uniqueness.R`: duplicate
  row_uid → fail; NA row_uid → fail; undeclared native dup → error; exempted
  dup → pass; exemption does not cover a wider violation.

### §4 documentation

- CLAUDE.md: one gotcha bullet — every processed survey RDS carries `row_uid`;
  its stability contract; native IDs are data, never sole keys; pointer to the
  key-declarations file.
- Per-survey docs pages: one line each on native ID availability/caveats.
- JEFF_MUST_INVESTIGATE: resolve the three open questions from the idnumber
  entry (mint: yes, engine-level; HK duplicates: keep + exempt per Jeff
  2026-08-10; automated check: built).
- docs/QA.md: add the check to the coverage map.

### §5 out of scope

GCB output (not built; declaration added dormant), AB W6 (not loaded), WVS
W4/W6 native IDs (absent in raw) and W3's dup-ridden S007, the non-survey scaffolds
(vdem/marpor/unga/unsc/oecd_dac — country-year units, different key
semantics), and any row deletion.

### §6 verification

1. Full-bank rebuild (engine change makes everything stale anyway).
2. Bank-wide assert: `row_uid` unique and non-NA in all twelve processed files.
3. Native-key duplicate counts must match the evidence table **exactly**; any
   drift is a new finding, not noise.
4. Stability proof: rebuild one survey twice; `row_uid` byte-identical.
5. `make audit-specs`, local `run_all`, and all fault-injection tests green.

## Post-rebuild evidence corrections (2026-08-10, exact-match verification)

The §6 exact-match rule surfaced two corrections to the evidence table, both
raw-verified as release-file artifacts and folded into the exemptions:

- **kipa_corruption: 75 surplus, not 74** — the cumulative 2004-2007 release
  carries one additional duplicate id inside its 2006 block.
- **lbs: 2,920 surplus, not 0** — `numentre` is not a within-country key in
  1997/1998/2000/2001/2002/2006/2010 (1998 alone: 2,841 surplus in raw). The
  original sample (2003, 2024) hit only clean years. numentre remains a
  traceability column; it is a usable key only in the fifteen clean years.
