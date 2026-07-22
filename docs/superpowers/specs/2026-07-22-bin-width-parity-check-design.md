# Bin-Width Parity Check (Layer 4, Check D) — Design

Date: 2026-07-22
Branch: `feat/audit-bin-width-parity`
Status: approved (design approved interactively 2026-07-22; findings-visible policy chosen)

## Problem

ABS Wave 5 fielded the institutional-trust battery on a 6-point bipolar scale;
`safe_6pt_to_4pt` collapses it to the 4-point target by merging **both poles**
(native 6,5 → 4; 2,1 → 1). The W5 top bin therefore absorbs two native
categories while every other wave's top bin absorbs one, mechanically
inflating W5 top-box shares ~2.4–4.6× in all 13 trust items, in every country
(confirmed 2026-07-21 from paper 05's bug report,
`paper-bank-05_thailand_trust_collapse/claudedocs/ABS-W5-trust-harmonization-artefact.md`).

No existing audit layer can catch this class: the mapping is *directionally*
correct, so label reconciliation, strict reversal, and battery coherence all
pass it legitimately. The gap is a check on the **shape of the mapping** —
whether the number of source categories feeding each target bin is constant
across waves.

## Goal

A deterministic Layer-4 check ("Check D") that, for every survey × variable,
compares the per-wave **bin signature** — how many source categories map into
each harmonized target value — and flags variables whose waves disagree.

## Non-goals

- No empirical raw→harmonized crosstab arm (Approach B). Static evaluation
  catches the whole class; the empirical arm needs per-survey raw loaders
  (ABS-only today) and is deferred. Header documents this.
- No distributional/statistical detection (top-box outliers) — conflates real
  attitude change with artefacts; explicitly rejected.
- No change to any harmonization spec or recode function. The check only
  reports. Fixing the ABS W5 seam itself (native `*_w5_6pt` columns, docs) is
  separate work.

## Approach (chosen)

**Static spec × registry evaluation.** For each survey, walk every YAML spec
variable, resolve each wave's rule exactly as the engine does
(`harmonize.R::resolve_wave_rule` semantics — mirrored, as
`04_strict_reversal.R` already does), and derive the wave's bin signature:

| Wave rule | Signature derivation |
|---|---|
| `method: identity` | All widths 1 over the spec's declared scale domain. |
| `method: recode` | Count widths directly from the YAML `mapping` (nulls → NA, not a bin). |
| `method: r_function` | Look up `src/r/utils/recoding_registry.yml`. If `requires_data: false` and numeric `input_scale`: call the function on the full input domain (`input_min:input_max`) with defaults — the engine passes no substantive extra args (`harmonize.R:222-228`), so defaults mirror production — and tabulate target ← source counts. |
| `method: derive`, `requires_data: true`, null/non-numeric scales, fn missing from registry, null source | `skip` row with explicit reason (missing registry entry additionally surfaces as `no_registry_entry`). |

A **bin signature** is the multiset of (target value → source-category count),
serialized like `4:2|3:1|2:1|1:2` (ABS W5 trust) vs `4:1|3:1|2:1|1:1`
(identity/pure reversal).

### Parity rule

Within a variable, over all non-skip waves:

- Signatures identical everywhere → `ok` (even if all waves collapse — a
  uniform 6→4 everywhere preserves cross-wave comparability).
- Signatures differ AND at least one wave has a bin of width ≥ 2 →
  **`parity_error`** on the offending wave rows (the wave(s) whose signature
  deviates from the modal signature; when signature counts tie, the baseline
  is the least-collapsed signature — all-width-1 preferred over width ≥ 2,
  then the wider domain, then alphabetical — so the collapsing wave, not the
  1:1 wave, carries the flag).
- Signatures differ only in domain coverage with all widths 1 (e.g. a wave
  whose scale is genuinely shorter, every bin still 1:1) → `warn`
  (cardinality drift, not a width artefact; midpoint-drop recodes like
  `collapse_middle5_to_4pt` stay all-width-1 and do NOT error).
- Only one usable wave → `ok` (nothing to compare).
- Variable exempted → `ok_exempt`.

### Exemptions

`src/config/_audit/bin_width_exemptions.yml`, same shape and philosophy as
`anchor_coverage_exemptions.yml`: exemption is a deliberate editorial act with
a `reason`, matched per (survey, variable), optional `survey:` restriction.
Ships with schema + header comments and **no seeded entries**: the 13 ABS W5
trust findings stay visible (user decision 2026-07-22), same treatment as the
ABS label-recon backlog.

## Components

1. **`src/r/audit/04_bin_width_parity.R`** — the check.
   Public API mirrors strict reversal: `compute_bin_width_parity(survey)` →
   tibble; `run_bin_width_parity(survey)` → writes
   `audit/reports/<survey>/04-bin-width-parity.csv` + prints summary.
   CLI: `--survey <s>` / `--all-surveys`. Exit 0 no errors / 1 any
   `parity_error`. CSV columns: `survey, variable, wave, method, fn,
   signature, n_bins, max_width, status, message`.
   Sources `_load_functions.R` for fn evaluation; reads specs from the
   survey's spec dir (ABS: `harmonize_validated/`), registry from
   `recoding_registry.yml`.

2. **`src/config/_audit/bin_width_exemptions.yml`** — empty exemptions
   scaffold with documentation header.

3. **`run_all.R` wiring** — new HARD module `.run_layer_4_binwidth`
   (`parity_error` rows fail the module, like L4 labels), new `L4 binwidth`
   column in SUMMARY.md table and tldr tally.

4. **`99_post_harmonize_gate.R` wiring** — added as a fourth check;
   report-only by default, fails the gate only under
   `HARMONIZE_AUDIT_GATE=block` (consistent with label recon). Crash of the
   check fails closed when blocking.

5. **`src/r/audit/test_bin_width_parity.R`** — fault-injection tests:
   - synthetic spec, one wave `safe_6pt_to_4pt` + others identity → exactly
     that wave flagged `parity_error` with signature `4:2|3:1|2:1|1:2`;
   - all waves same collapse fn → `ok`;
   - exempted variable → `ok_exempt`;
   - `requires_data: true` fn → `skip`;
   - `method: recode` with a merged bin → `parity_error` (no registry needed);
   - midpoint-drop recode (5→4 with 5→null) → no error (all widths 1);
   - fn absent from registry → `no_registry_entry`;
   - **real-ABS regression**: sweep flags exactly the 13 trust items, W5 rows.

6. **Docs** — `docs/QA.md`: new row(s) in the caught/missed fault-injection
   table + a Check D section stating what it provably catches (cross-wave
   bin-width divergence declared in specs/registry) and what it does NOT
   catch (collapses uniform across waves; `requires_data` fns;
   raw domains wider than the registry declares — deferred Approach B;
   anything in `derive`).

## Error handling

- Missing registry file → hard stop (same as strict reversal).
- Malformed spec entry → `skip` row with message, never a crash; the module
  wrapper in `run_all.R` still counts a crashed script as module `fail`.
- Fn evaluation wrapped in `tryCatch` → evaluation error becomes `skip` with
  the condition message (a fn that errors on its declared domain is itself a
  finding worth surfacing in `message`).

## Expected first-sweep result

ABS: 13 `parity_error` variables (the trust battery, W5). Other surveys: any
additional hits are triage leads — legitimate documented seams get exempted
with reasons; undocumented ones are new findings of exactly the class this
check exists for.
