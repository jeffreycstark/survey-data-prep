# MARPOR / CMP (Manifesto Project)

**Status**: Scaffold — Deliverables A, B and C all complete.
**Unit of observation**: **party × election** (NOT individual respondents).
**Pinned release**: `MPDS2025a` (corpus version `2025-1`).
**Coverage**: 5,285 manifestos | 67 countries | 822 elections | 1920–2025.

Requested by paper-bank 25 (`papers/25-cmp/`), "Electoral Rules Move Dispersion,
Not Position" (Research & Politics research note). Full spec:
`paper-bank-25/papers/25-cmp/DATA-REQUEST.md`.

---

## ⚠️ Not a survey — no verbatim question dictionary

`CLAUDE.md` makes a verbatim question dictionary mandatory "for every survey".
**MARPOR is not a survey**: there is no questionnaire and no respondent, so that
requirement does not apply, exactly as it does not apply to V-Dem. This is
recorded here so a later audit does not flag it as a gap.

What replaces it is the **CMP coding-scheme codebook** (the `per101`–`per706`
category definitions), stored at
`data/marpor/raw/MPDS2025a/cmp_handbook_2021_version_5.pdf`.

> Acquired directly from the Manifesto Project rather than through `manifestoR`:
> `mp_codebook(version = "2025-1")` returns HTTP 404 and `mp_describe_code()`
> connects but returns `NA` for both title and description, so neither serves the
> category definitions. The bundled `v5_categories()` is only a character vector
> of codes, not definitions.
>
> The repo's blanket `*.pdf` ignore rule was silently excluding this file even
> though the policy note at the foot of `.gitignore` states codebooks are
> tracked. A narrow `!data/*/raw/**/*.pdf` exception was added so the codebook
> actually survives a fresh clone — this also recovers the DES codebook and
> change log under `data/des/raw/v5_0/`.

---

## Release pinning

`MPDS2025a` is pinned in `0_load_marpor.R` (`MARPOR_RELEASE`). **Do not float it.**
CMP revises scores between releases, and R&P expects a reproducible data
citation. The request's `MPDS2024a` was an example; 2025a is the current release.

## Credential

Requires a free API key from `manifesto-project.wzb.eu`. It lives in the **macOS
Keychain** (service `marpor_api_key`) and is exported as `MARPOR_API_KEY` by
`~/.secrets`, following the house `get_keychain_secret()` pattern. No key is
stored in this repo.

`marpor_apikey()` resolves it through a fallback chain, because a non-interactive
`Rscript` call does **not** source `~/.zshrc` and therefore never sees the env var:

1. `Sys.getenv("MARPOR_API_KEY")` — interactive shells
2. macOS Keychain via `security find-generic-password` — non-interactive `Rscript`
3. `.secrets/manifesto_apikey.txt` — optional gitignored local override

---

## Deliverable A — `marpor_party_election.rds` / `.parquet` ✅

5,285 rows × 119 columns. One row per party per election; keyed `party` × `edate`
(uniqueness asserted at build time).

Aggregation to country-election level (seat-weighted mean / SD of RILE) is a
**paper-specific** derived variable and stays in paper-bank.

### ⚠️ Do not drop the category block

The full `per101`–`per706` vector, the 32 subcategory columns, `peruncod` and
`total` ship intact **on purpose**. The BLM bootstrap treats each manifesto's
coded quasi-sentences as a multinomial draw across categories; without the
category vector and the total, the measurement-error correction — the paper's
whole contribution — is impossible.

### Parent categories vs subcategories

`manifestoR` exposes **56 parent** categories (`^per[0-9]{3}$`) and **32
subcategory** columns from the extended scheme (`per103_1`, `per608_3`, …).
Subcategories break their parent down further, so **summing parents AND
subcategories double-counts**. Parity checks and multinomial reconstruction must
use the parent set only — `marpor_parent_categories()` returns it.

### Derived columns added here

| Column | Meaning |
|---|---|
| `eyear` | election year, from `edate` |
| `seatshare` | `absseat / totseats` |
| `per_sum` | 56 parents + `peruncod`; the parity diagnostic |
| `n_coded` | **the correct multinomial N** — see below |
| `blm_usable` | `total` present and > 0 and `per_sum` > 0 |

---

## Acceptance checks (DATA-REQUEST §7)

Run against `MPDS2025a` on 2026-07-28.

### 1. Do `per*` sum to ~100? — **qualified pass, with a real finding**

| Outcome | Rows | Share |
|---|---|---|
| Sum within 99–101 | 4,313 | 81.6% |
| Sum **below** 100 (nonzero) | 873 | 16.5% |
| Sum exactly 0 (uncoded manifesto) | 99 | 1.9% |

All 873 off-sum rows fall **below** 100 (max exactly 99.00); none exceed it, and
only 22 carry subcategory mass — so this is **not** subcategory double-counting.

**The multinomial reconstruction is sound.** Implied counts `per_j × total / 100`
recover integers: e.g. Sweden 1944 (`total` = 52) has per values 1.9 / 9.6 / 3.8,
which are exactly 1/52, 5/52, 2/52. Residual deviation from integrality is
attributable to MPDS publishing percentages rounded to 1–3 decimals (76% of rows
within 0.01 of an integer, 87% within 0.05).

**⚠️ The finding that matters for Deliverable B**: in those 873 rows MPDS leaves
uncoded quasi-sentences out of `peruncod`, so **`total` overstates the coded
base**. The multinomial N for the BLM bootstrap is therefore `n_coded`
(= `total × Σparents / 100`), **not** `total`. Using `total` would understate
per-manifesto uncertainty by treating uncoded sentences as if they had been
coded. `n_coded` is precomputed in the shipped table.

The 99 zero-sum rows are all-NA across parents and have NA `total` — genuinely
uncoded manifestos, and exactly the rows excluded by `blm_usable`.

### 2. Quasi-sentence total present? — **pass**

The column is named **`total`** in MPDS2025a (the request flagged that this name
has moved between releases; confirmed against this release).

- missing: 106 / 5,285 (2.01%)
- zero: 0
- **usable for BLM: 5,179 (97.99%)**
- distribution: min 8, median 266, mean 637, max 10,746

This bounds Deliverable B at ~98% of manifestos.

### 3. `absseat` / `totseats` missingness by country — **pass, better than feared**

Overall: `absseat` 6.47% missing, `totseats` 4.22%, `pervote` 7.06%.

The request warned that thin seat data in the post-communist cases would
materially change the feasibility verdict. **It does not.** Croatia 14.3%,
Bulgaria 13.6%, Slovakia 8.7%, Serbia 8.6%, Romania 7.7%, Lithuania 6.7%,
North Macedonia 5.4% — all usable for a seat-weighted primary outcome.

Only 9 of 67 countries exceed 50% `absseat` missingness, and those same 9 are
100% missing on `pervote` too, so they are excluded by any weighting scheme.

### 4–5. Election coverage around priority reform cases — **GATE PASSES**

Criterion: ≥3 CMP-covered pre-reform and ≥2 post-reform elections, reform
election itself covered.

| Case | Pre | Post | Verdict |
|---|---|---|---|
| France 1986 (→ PR) | 10 | 9 | **usable** |
| France 1988 (→ 2-round maj.) | 11 | 8 | **usable** |
| New Zealand 1996 (FPTP→MMP) | 17 | 9 | **usable** |
| Japan 1996 (SNTV→MMM; 1994 reform) | 12 | 9 | **usable** |
| Italy 1994 (PR→MMM; 1993 reform) | 12 | 7 | **usable** |
| Italy 2006 (2005 reform) | 15 | 4 | **usable** |
| Italy 2018 (Rosatellum) | 18 | 1 | fails — only 1 post election coded |
| Israel 1996 (direct PM) | 13 | 12 | **usable** |
| Israel 2003 (repeal direct PM) | 15 | 10 | **usable** |
| Bulgaria 1991 | 1 | 9 | fails — no pre-transition history |
| Croatia 2000 | 3 | 7 | **usable** |
| Romania 2008 | 5 | 3 | **usable** |
| Ukraine 1998 | 1 | 7 | fails — no pre-transition history |
| Ukraine 2006 (full PR) | 3 | 5 | **usable** |
| Ukraine 2012 (back to mixed) | 5 | 3 | **usable** |

**12 of 15 usable, against a gate threshold of 8 → PASS**, and this is only the
priority list, not an exhaustive sweep of rule changes.

**France 1986/1988 — the within-case reversal the brief flagged as unusually
valuable, and the reason an absorbing-treatment estimator was rejected — is
fully covered on both sides.**

The three failures are structural, not fixable: Italy 2018 has only one
post-reform election coded so far; Bulgaria 1991 and Ukraine 1998 are
founding-era transitions with no pre-reform CMP history. This is the
post-communist coverage gap the brief anticipated, and it costs 2 cases without
threatening the design.

---

---

## Deliverable C — `electoral_systems.rds` ✅

Country × election, lower-chamber legislative only. 1,826 elections | 166
countries | 1919–2021.

Spine is **Bormann & Golder, *Democratic Electoral Systems* v5.0**
(`data/des/raw/v5_0/`, from mattgolder.com), with CLEA
(`data/processed/clea_lc_20251015.RData`, already in repo) joined on as the
observed-magnitude cross-check.

### ⚠️ DES encodes missing as `-99` / `-88`, not `NA`

`seats`, `tier1_avemag`, `tier1_districts`, `upperseats`, `uppertier`,
`tier2_districts`, `enep` and `enpp` all carry sentinel codes. Left uncleaned,
`log(mag_eff)` is silently `NaN` and any mean over the raw column is nonsense.
They are converted to `NA` in the loader; do not remove that step.

### Tier-aware effective magnitude

```
mag_eff = (seats_tier1 * mag_tier1_ave + upperseats * mag_upper) / seats
```

a seat-weighted average of tier magnitudes, reducing **exactly** to
`mag_tier1_ave` for single-tier systems. The components ship alongside so the
paper can substitute its own operationalization without re-deriving anything.
99.2% non-missing.

**Validation**: DES tier-1 magnitude vs CLEA observed magnitude correlates
**r = 0.952** (n = 941 matched elections). The CLEA join matches 51.6% of DES
elections on country-name + year + month; the unmatched remainder is a join
limitation, not missing data — DES remains authoritative for magnitude.

### ⚠️ Legal threshold is NOT included

The request asks for it. **DES v5.0 has no threshold column** (verified against
the 50-column v5.0 schema). It is therefore absent rather than silently imputed.
If the paper needs it, it must come from another source — Carey/Hix, or
hand-coding the treatment cases only.

---

## Outstanding

Nothing blocking. Two known limitations, both documented above and neither
fixable from the shipped sources: **legal threshold** (absent from DES v5.0) and
**Franzmann–Kaiser standard errors** (not well defined per-manifesto).

## Pipeline

Run in this order — `99` depends on `0`, and `2`/`98` depend on `99`.

```bash
Rscript src/r/data_prep_modules/marpor/0_load_marpor.R            # download + cache MPDS2025a
Rscript src/r/data_prep_modules/marpor/99_create_final_dataset.R  # Deliverable A
Rscript src/r/data_prep_modules/marpor/2_bootstrap_manifesto_se.R # Deliverable B (slow)
Rscript src/r/data_prep_modules/marpor/97_build_electoral_systems.R # Deliverable C
Rscript src/r/data_prep_modules/marpor/98_acceptance_checks.R     # §7 checks + TASK 0 gate table
```

The numeric prefixes follow the house V-Dem convention (`0_load_*`,
`99_create_final_dataset`); `2`, `97` and `98` are additions this module needs
and do not correspond to the survey pipeline's `2_harmonize_all.R` — there is no
harmonization step here, because there are no questionnaire items to reconcile.
