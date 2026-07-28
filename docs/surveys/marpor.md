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
> tracked. Narrow `!data/marpor/raw/**/*.pdf` and `!data/des/raw/**/*.pdf`
> exceptions were added so the codebook survives a fresh clone — this also
> recovers the DES codebook and change log under `data/des/raw/v5_0/`.
>
> Deliberately **not** the blanket `!data/*/raw/**/*.pdf`: that pulls in 261
> files / 535 MB of questionnaires and methods reports across every survey.
> Tracking those may well be right — the policy note implies it — but that is a
> repo-size decision for Jeff, not a side effect of a MARPOR commit.

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

### ⚠️ `corpusversion` ships the literal string "NA", not a real NA

MPDS delivers `corpusversion` as a **character** column in which absent values
are the four-character string `"NA"` — 3,128 of 5,285 rows in MPDS2025a (59%).
`is.na()` returns **FALSE** for every one of them, so a filter, `group_by()` or
join on this column silently acquires a bogus `"NA"` level, and
`sum(is.na(corpusversion))` reports 0 when in truth most of the column is empty.

This matters because §2 of the data request names `corpusversion` as the
provenance stamp the paper cites its exact release from.

`99_create_final_dataset.R` converts it to a real `NA`. The fix is **narrowly
scoped to this one column on purpose** — a party abbreviation of `"NA"` would be
perfectly legitimate (none currently is), so a blanket sweep across character
columns could destroy real data in a future release.

The 2,157 populated rows all read `2025-1`: these are the manifestos present in
the **corpus**. Main-dataset-only manifestos have no corpus version, which is
what the blank means — it is not missingness to be imputed. The pinned release
is recorded independently in `0_load_marpor.R` (`MARPOR_RELEASE`,
`MARPOR_CORPUS_VERSION`), so provenance does not depend on this column.

Checked and clean in the same pass: `datasetversion` (all `2025a`),
`partyabbrev`, `parfam`. `testresult` uses proper real `NA`s (1,838).

### Derived columns added here

| Column | Meaning |
|---|---|
| `eyear` | election year, from `edate` |
| `seatshare` | `absseat / totseats` |
| `per_sum` | 56 parents + `peruncod`; the parity diagnostic |
| `n_coded` | `total × Σparents / 100`; the BLM N **for parents-only cells** — see check 1 |
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
uncoded quasi-sentences out of `peruncod`, so **`total` overstates the base the
category cells actually account for**. Drawing `total` sentences therefore
understates per-manifesto uncertainty.

The multinomial N is **`n_accounted`** (= `total × per_sum / 100`), **not**
`total`. It is computed in `2_bootstrap_manifesto_se.R`.

> **Superseded:** an earlier revision of this page named `n_coded`
> (= `total × Σparents / 100`) as the N. That is wrong when paired with
> manifestoR's default resample cells, which include `peruncod`: `n_coded` has
> already removed the uncoded mass, so leaving `peruncod` in as a cell discounts
> it twice and inflates the SE. `n_coded` remains correct only with
> parents-only cells, and ships in that pairing as the `rile_se_coded`
> sensitivity column. See "Deliverable B" below.

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

### 4–5. Election coverage around priority reform cases — **preliminary, superseded**

> ⚠️ **This table is a hand-curated first pass and is NOT the gate result.** The
> authoritative answer is the DES-driven sweep in "TASK 0 gate" below, which
> reads every rule change in the data rather than a chosen fifteen. Two rows
> here are wrong once treatment is coded continuously — see the corrections
> under the table.

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

#### ⚠️ Two corrections to the table above

**Israel 1996 and 2003 are not usable for this design at all.** Both are marked
"usable" above on election-count grounds, but the direct election of the Prime
Minister and its repeal changed **executive** selection, not the legislature.
Israel elects its Knesset from a single 120-seat national district throughout;
`mag_eff` is a flat 120 across 1992, 1996, 1999, 2003 and 2006, and DES does not
flag any of them as a legislative rule change. Under continuous treatment coding
they contribute exactly zero identifying variation.

**Romania 2008 has no measurable treatment.** It clears the election-count
criterion (5 pre / 2 post) but effective magnitude is `NA` on **both** sides, so
Δ log magnitude cannot be formed. It is the single NA in the sweep below.

Net: of the 12 rows called "usable" above, **9** actually carry a continuous
treatment. This is why the count-based gate and the design-relevant N differ,
and why the sweep below is the number to report.

---

## TASK 0 gate — the authoritative result

Produced by `98_acceptance_checks.R`; full table at
`outputs/marpor/task0_rule_change_coverage.csv`.

| Stage | N |
|---|---|
| DES rule changes, all countries | 134 |
| …in CMP-covered countries | 104 |
| …usable (≥3 CMP pre, ≥2 post) | **49** |
| …with non-zero Δ log effective magnitude | **35** |

**VERDICT: PASS.** The brief's threshold is ≥8 usable changes (5–7 → proceed but
report the position null as underpowered; <5 → stop). It clears on either count.

### Report 35, not 49

The gate counts *changes*; the paper codes treatment **continuously**, as Δ log
effective magnitude. A rule change that restructures the system without moving
magnitude contributes no identifying variation. Of the 49:

- **13** have `delta_log_mag_eff == 0` — rule changed, magnitude did not
  (Albania 2005, Georgia 2016, Greece 2012 and both 2015 elections, Israel 1973,
  Lithuania 2004, Moldova 2014, Poland 2005, Slovakia 2012, Slovenia 2008,
  Turkey 1965 and 1969)
- **1** has `delta_log_mag_eff == NA` — Romania 2008

**35** is the design-relevant N and the number the paper should state.

### The reversals survive

The within-case reversals — the reason an absorbing-treatment estimator was
rejected — are intact and exactly symmetric:

| Case | pre → post magnitude | Δ log |
|---|---|---|
| **France 1986** (→ PR) | 1.00 → 5.79 | **+1.756** |
| **France 1988** (→ 2-round maj.) | 5.79 → 1.00 | **−1.756** |
| Italy 1994 (PR→MMM) | 19.69 → 2.22 | −2.182 |
| Italy 2006 | 2.22 → 23.73 | +2.369 |
| Ukraine 2006 (full PR) | 113.0 → 450.0 | +1.382 |
| Ukraine 2012 (back to mixed) | 450.0 → 113.0 | −1.382 |
| New Zealand 1996 (FPTP→MMP) | 1.00 → 25.75 | +3.248 |
| Japan 1996 (SNTV→MMM) | 3.96 → 7.87 | +0.687 |

That France, Italy and Ukraine each reverse to the same magnitude they came from
is a genuine validation of the tier-aware `mag_eff` construction, not a
coincidence — the pre and post values are computed independently per election.

### ⚠️ `prev_mag` is gone from the CSV

Through commit `251764e` the coverage CSV carried a column named `prev_mag` that
actually held the **post**-change magnitude (`select(prev_mag = mag_eff, …,
mag_eff)` dedupes to one column in dplyr). Anything differencing against it was
differencing a value against itself. It is replaced by `mag_eff_pre` and
`mag_eff_post`, with the pre value recovered as
`mag_eff_post / exp(delta_log_mag_eff)`. **Update any paper-side code that read
`prev_mag`.**

---

## Deliverable B — `marpor_manifesto_se.rds` ✅

Per-manifesto Benoit–Laver–Mikhaylov (2009) bootstrap standard errors, keyed
`party` × `edate`. **5,179 rows** (the 106 manifestos with no usable
quasi-sentence total are excluded).

### Parameters the paper must report

| Parameter | Value |
|---|---|
| Replications | **1,000** |
| Seed | **20260728** |
| Seeding scheme | **per row**, `seed + row index` |
| Release | MPDS2025a (corpus 2025-1) |
| Engine | `manifestoR::mp_bootstrap()` 1.6.3 |

Each manifesto is seeded independently, so output is identical regardless of how
many cores `mclapply` uses and adding or removing a scheme does not perturb the
others. Do not replace this with a single top-level `set.seed()`.

### The three N/cell schemes

The multinomial N must match the cells it is spread across. All three ship, so
the choice can be reported as a robustness check rather than defended in prose.

| Column | N | Cells | Role |
|---|---|---|---|
| `rile_se` | `n_accounted` | 56 parents + `peruncod` | **primary** |
| `rile_se_mrdefault` | `total` | 56 parents + `peruncod` | manifestoR default |
| `rile_se_coded` | `n_coded` | 56 parents only | sensitivity |

Median ratio of primary to each of the other two is 1.0000, because the schemes
coincide *exactly* on rows where `peruncod = 0` and the categories sum to 100 —
81.6% of the table.

⚠️ **Do not read that as "the correction doesn't matter."** The whole-table
median is 1.0000 only because most rows are unaffected by construction. On the
**870 rows (16.8%) the correction actually touches** — those where `per_sum ≤ 99`,
i.e. where MPDS omits uncoded mass from `peruncod` — the primary SE runs
**+4.3% above the manifestoR default** at the median. `rile_se_coded` agrees with
primary on those rows (ratio 1.0000), which is expected: both remove the same
unaccounted mass, differing only in whether `peruncod` stays as a resample cell.

So the scheme choice is not load-bearing *overall*, but it is not negligible on
the affected subset, and it moves in the conservative direction — larger SEs,
making the paper's dispersion result harder to obtain rather than easier.

Distribution of `rile_se`: median **4.12**, IQR 2.40–6.52, max 35.64.

### ⚠️ MPDS's published `rile` does not always match its own `per*` values

`rile_boot` is `manifestoR::rile()` recomputed from the published category
vector. It reproduces the shipped `rile` to ≤0.001 for **99.2%** of rows — but
not all:

- **41 rows (0.79%) differ by more than 0.05**, max gap **8.36 rile points**
- **all 41 are Mexico**, all from the **1998/2002 coding rounds** (elections
  1952–2000, worst in the 1990s)
- Mexico manifestos coded later reconcile: every 2010s row, 21 of 24 in the 2000s

This is a source-side inconsistency in an early Mexico coding round, not a fault
in the resample cells — the discrepancy does not track `per_sum`, and no
category reassignment reproduces it. Both levels ship (`rile` = MPDS published,
`rile_boot` = recomputed) with `rile_parity_gap` and `rile_parity_flag`.

**`rile_se` is the SD of the recomputed rile.** For flagged rows it describes
the dispersion of `rile_boot`, not of the shipped `rile`. **If the paper uses
Mexico as a treatment case, decide explicitly which level to pair the SE with.**

The build asserts structurally rather than on a hard maximum: it halts if more
than 1.5% of rows breach tolerance, or if the discrepancy stops being confined
to a single country.

### One degenerate row

Australia 1951 (Country Party) puts all 42 coded quasi-sentences in `per703`,
which is outside the RILE index. Every resample returns `rile = 0`, so
`rile_se = 0` under all three schemes. Correct, not a failure; excluded from the
summary ratios only.

### Franzmann–Kaiser SEs — not shipped

The request asked for them "if cheap". They are not. FK needs country
party-system base values estimated across the whole sample, so called on a
single manifesto — inside or outside `mp_bootstrap` — it returns `NaN`. A joint
bootstrap of the entire table would be a *different estimand*: each manifesto's
SE would absorb other manifestos' resampling. FK point estimates on the full
table remain computable (2,977 of 5,179 non-`NaN`); only the SEs are out.

**Shipped instead**: `logit_rile_se` (Lowe et al. 2011). It is row-wise, so it
bootstraps under the identical procedure at no extra design cost, and gives the
paper a working robustness scale. Median `logit_rile_se` = 0.185, no
non-finite values. This is a **substitute, not the requested quantity** — flagged
for the paper rather than swapped in silently.

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

Nothing blocking. Three items for the paper to decide or source elsewhere, all
documented above and none fixable from the shipped sources:

1. **Legal threshold** — absent from DES v5.0; not imputed.
2. **Franzmann–Kaiser standard errors** — not well defined per-manifesto;
   `logit_rile_se` ships as a substitute.
3. **The 41 Mexico rile-parity rows** — MPDS's published `rile` disagrees with
   its own `per*` values. Only matters if Mexico is used as a treatment case,
   and then only for which rile level the SE is paired with.

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
