# UNGA voting + UNSC membership

**Status**: Deliverables 2.1, 2.2, 2.3 complete. 2.4 (aid) and §3 (crosswalk) outstanding.
**Unit of observation**: country × year (ideal points), country × roll-call (votes),
country × term (UNSC membership). **NOT individual respondents.**
**TASK 0 gate**: **PASS** — see below.

Requested by paper-bank 24 (`papers/24-unsc/`), "The Half-Life of Purchased
Alignment" (Research & Politics research note). Full spec:
`paper-bank-24/papers/24-unsc/DATA-REQUEST.md`.

---

## ⚠️ Not surveys — no verbatim question dictionary, no YAML harmonize spec

Same standing exemption as V-Dem and MARPOR. There is no questionnaire and no
respondent here, so the `CLAUDE.md` "every survey" requirements do not apply.
Recorded so a later audit does not flag it as a gap.

---

## Deliverable 2.1 — `unga_idealpoints.{rds,parquet}` ✅

Bailey–Strezhnev–Voeten dynamic ideal points. **11,610 rows | 198 states | 1946–2025.**

Source: Harvard Dataverse `doi:10.7910/DVN/LEJUQZ`, **v38.0 (2026-04-03)**.

The request flagged `ideal_point_se` as mattering — the paper pre-empts "ideal
points are estimated, not observed" by propagating that uncertainty. The release
ships posterior **quantiles** rather than a summary SE, so the file carries
`ideal_point_q5/q10/q50/q90/q95` and a derived `ideal_point_se_derived`, present
for **100%** of usable rows.

## Deliverable 2.2 — `unga_votes.{rds,parquet}` ✅

Roll-call level. **1,283,746 rows | 6,551 roll-calls | 1946–2022.**

Source: same deposit, **v33.0 (2024-06-24)**, `UNVotes-1.RData`.

`vote` is the labelled factor, `vote_raw` the native integer — the request is
explicit that not-member must not collapse into absent, and it doesn't:

| yes | abstain | no | absent | not_member |
|---|---|---|---|---|
| 742,803 | 118,059 | 70,490 | 96,988 | 255,406 |

80,369 rows carry the US State Department key-vote flag; the six `issue_*` flags
are present for the stable-issue-subset robustness check.

### ⚠️ 88 rows have no country identity

`country_text_id`, `country_name` and `COWcode` are **all NA** on 88 rows
(0.0069%). Small, but they silently turn `==` comparisons into `NA`, so anything
joining on country must filter them explicitly. `98_task0_gate.R` does.

### ⚠️ The two UNGA files are from DIFFERENT deposit versions

Ideal points are v38.0; votes are v33.0. **This is not fixable by re-pulling.**

**`UNVotes` was REMOVED from the deposit after v33.0.** Versions v34.0 (Dec
2024) through v39.0 (Jul 2026) contain no roll-call file at all — only ideal
points and agreement scores. v33.0 is the last version that ever shipped
roll-calls, so the extract we hold is already the newest available from this
DOI. A search of Harvard Dataverse turned up no newer replacement deposit.

### ⚠️ DO NOT TRUST THE `year` COLUMN IN THE VOTES FILE

Coverage ends **2024**, not 2022 — the `year` column is wrong at the tail, in
the SOURCE data. Every session-78 roll-call is labelled `year = 2022` though
those votes are dated **2023-09-01 to 2024-06-04**. Verified against the
archived raw `UNVotes-1.RData`, whose row count matches ours exactly, so this is
an upstream Voeten defect we inherit rather than a build error.

Taking `year` at face value understates roll-call coverage by two years.
**Derive calendar year from `date`.** `98_task0_gate.R` does; anything building
the agreement-rate outcome must too.

(Separately, 1.5% of rows have `year != year(date)` because a session spans a
New Year. That part is benign — only the session-78 block is actually wrong.)

## Deliverable 2.3 — `unsc_membership_terms` / `_cy` ✅

Non-permanent members only, P5 excluded. **296 terms | 590 country-years | 1970–2028.**

Source: Wikipedia roster, archived under `data/unsc/raw/` with its revision id,
parsed by `src/python/unsc_membership/parse_wikipedia_unsc.py`.

**Structural validation passes**: every year 1970–2025 sums to exactly 10 seats,
which is the check the request specifies as the error detector. Getting there
caught a real defect — Wikipedia's `rowspan` *is* the term length, and assuming a
flat two years double-counted the Italy (2017) / Netherlands (2018) **split
seat**, throwing 2018–19 to eleven. Carried as `split_term` (2 terms).

1969 and 2028 show 5 seats. Those are **window edges, not errors**: the file
captures terms ending 1970+, so the 1968–69 cohort is only half present, and
2028 holds only the cohort elected so far.

The asterisk in the source marks the **Arab seat** (alternating between the
African and Asia-Pacific groups), not a split term — carried as `arab_seat`.

### ⚠️ Second source NOT yet reconciled

The request requires **two independent sources reconciled** plus **15 hand-checked
country-terms recorded in this page**. Neither is done. The UN's own roster at
`un.org/securitycouncil` is reachable (an early 403 was the default curl
User-Agent, not bot-blocking). The 10-seats-per-year check is strong evidence the
parse is right but is **not** a substitute for reconciliation. **This is an open
requirement, not a closed one.**

---

## TASK 0 gate — **PASS**

`98_task0_gate.R`. Gate: ≥100 exits with a complete +5 post-exit window, ≥60 with
+10; if +10 fails but +5 holds the design truncates to +5.

An **exit** is the end of a non-permanent term. Terms run two calendar years from
1 January, so a 2010–11 term exits end-2011 and its +5 window is 2012–16. A
window counts only if the state has a non-NA ideal point in **every** year.

| Window | Exits fitting coverage | Complete | Needed | |
|---|---|---|---|---|
| +5 | 256 | **253** | 100 | PASS |
| +10 | 230 | **227** | 60 | PASS |

**No truncation required — the full +10 design is viable**, with 3.8× the needed
events. Criterion 1 answered: ideal-point coverage **ends 2025**, and the tail is
dense (190 states in 2025).

### The three incomplete windows are real history, not data gaps

| Case | +10 | Why |
|---|---|---|
| East Germany 1980–81 | 8/10 | merged into DEU 1990 — genuine state death |
| SFR Yugoslavia 1988–89 | 3/10 | FRY **suspended from the UNGA 1992–2000** |
| Guinea-Bissau 1996–97 | 8/10 | civil war + 1999 coup; lost 2000–01 |

**Guinea-Bissau must not be read as dissolution** — it is extant through 2025 and
merely stopped casting recorded votes (2002 has 3). Only East Germany is a state
that ceased to exist.

### Second outcome is ~32 events lighter

The agreement-rate outcome is built from the roll-call file, which ends 2022:

| Window | Ideal-point outcome | Agreement-rate outcome | Δ |
|---|---|---|---|
| +5 | 253 | **225** | −28 |
| +10 | 227 | **195** | −32 |

Both still clear the gate. But **if the two outcomes are co-primary the binding N
is the smaller figure**, and the headline should not be 227.

**This gap is NOT closable.** An earlier revision of this page said refreshing
the votes extract to v38.0 would close it. That was wrong on both counts: v38.0
ships no roll-call file at all, and the shortfall is driven by the roll-call
series genuinely ending mid-2024 against ideal points running to 2025 — not by
version skew. Deriving calendar year from `date` rather than the broken `year`
column recovers 5 events at +5 (220 → 225) and none at +10.

### Criterion 4 — crosswalk **PASS**

Two parts, both clean.

**UNSC → UNGA**: every UNSC term's `country_text_id` resolves in the ideal-point
file — **zero unmatched**. This is what licenses reading 253/227 as real rather
than as crosswalk attrition.

**UNSC → V-Dem (the moderator)**: **249 of 256** exits have a complete +5 V-Dem
window. Exactly **one** loses the moderator entirely — the **Byelorussian SSR**,
a UNGA member from 1945 whose UNSC term predates V-Dem's coverage of independent
Belarus. Ukraine has the same 1945–91 gap, but its UNSC exits fall inside V-Dem
coverage.

Built by `src/r/data_prep_modules/lookups/99_country_code_crosswalk.R` →
`data/lookups/country_code_crosswalk.csv` (446 rows, 246 ISO3) plus
`country_code_coverage_report.csv`.

#### ⚠️ The silent-NA trap is real, and it hits UNSC members

V-Dem has **no row for YUG, CSK or VCT**. YUG and CSK are not obscure — both held
non-permanent seats with exit events inside the window. **Joining V-Dem on ISO3
alone silently NAs the regime moderator for those events**, and the truncated
window then looks like an artefact rather than the join failure it is.

Resolved by joining on COW where ISO3 disagrees:

| Source ISO3 | V-Dem ISO3 | Shared COW |
|---|---|---|
| `CSK` Czechoslovakia | `CZE` | 315 |
| `YUG` SFR Yugoslavia | `SRB` | 345 |
| `YAR` North Yemen | `YEM` | 678 |

**COW is not unique either** — 345 covers both YUG and SRB, 315 both CSK and CZE,
678 both YAR and YEM. Neither key is safe alone; the pair plus a year range is
what disambiguates, which is why the crosswalk carries `valid_from`/`valid_to`.

21 ISO3 remain unresolved, and these are **genuine V-Dem coverage gaps, not
naming mismatches** — Andorra, Antigua, Bahamas, Belize, Brunei, Dominica,
Micronesia, Grenada, Kiribati, St Kitts, St Lucia, Liechtenstein, Monaco,
Marshall Is, Nauru, Palau, San Marino, Tonga, Tuvalu, St Vincent, Samoa. V-Dem
does not cover most microstates. None of them has ever held a UNSC seat.

---

## Deliverable 2.4 — `dac_aid_bilateral.{rds,parquet}` ✅

**944,968 rows | 1960–2024 | donor × recipient × year.** Built by
`src/r/data_prep_modules/oecd_dac/99_create_final_dataset.R`.

| | |
|---|---|
| Bilateral donors | 50 |
| Multilateral | 125 |
| Aggregates | 9 |
| Disbursements | 525,762 |
| Commitments | 419,206 |
| Bilateral→bilateral rows | 258,917 |

Decisions of 2026-07-29: Table 2a primary with CRS alongside; multilaterals
retained and flagged but excluded from weighting; base year as the release ships.

### ⚠️ `donor_type == "aggregate"` rows are SUMS of other rows

`ALLD` (all official donors), `DAC`, `G7`, `DACEU`… Filter to
`donor_type == "bilateral"` before summing anything, or totals are
double-counted several times over.

### ⚠️ DAC2A is disbursements only — commitments come from DAC3A

MEASURE 305 is declared in the DAC2A codelist but returns `NoResultsFound` for
every query. Commitments are therefore pulled from **DAC3A** ("Aid (ODA)
commitments to countries and regions"), same donor × recipient × year
granularity, starting **1970** — exactly the paper's universe. Better than
sourcing commitments from CRS, which is activity-level. CRS is still wanted for
sector detail and is **not yet pulled**.

### ⚠️ The two tables use DIFFERENT constant-price base years

**DAC2A is based 2022; DAC3A is based 2024.** `oda_usd_const` is therefore **not
comparable across `source_table`**, and differencing a commitment against a
disbursement in constant terms is wrong without re-basing. `const_base_year`
ships per row so this cannot happen silently. `oda_usd_current` **is** comparable
across both.

### ⚠️ Acquisition hazard — silent truncation

The SDMX endpoint returns **HTTP 200 on truncated responses**, and curl writes
the partial body without error. Three of eight DAC2A chunks were silently short
on the first pull: one had lost **57%** of its rows, and the 1980s came back as
12 rows. The loader now **fails on any year gap**. The endpoint also 403s on
default curl/python User-Agents and needs a browser UA — the same trap already
documented for un.org.

Raw extracts (141 MB) are gitignored; `RETRIEVED.txt` and `cl_area_org.csv` are
tracked so the pull is reproducible.

### Gate criterion 3 — aid coverage **PASS**

Bilateral aid is **dense from 1961** (≥100 recipients/year), so the paper's
entire 1970+ universe is covered. **This vindicates the Table 2a choice**: CRS
disbursements would have been empty until ~2002.

- **158 of 241** exits have a complete +5 post-exit aid window
- **78** exits have no post-exit aid at all — these are UNSC members that are
  **donors**, not recipients. A real category, not a coverage gap.

158 is the binding N for anything aid-conditional, and still clears the ≥100 bar.

---

## TASK 0 — all four criteria answered, gate PASSES

| Criterion | Result |
|---|---|
| 1 ideal-point coverage | ends **2025**, 198 states, SE on 100% |
| 2 post-exit windows | **253** complete +5, **227** complete +10 (need 100 / 60) |
| 3 aid coverage | dense from **1961**; **158** of 241 exits with a complete +5 aid window |
| 4 crosswalk | **249** of 256 exits with a complete +5 V-Dem window; 1 loss (BLR) |

Binding N depends on what the specification conditions on: **227** for the
ideal-point outcome at +10, **195** if the agreement-rate outcome is co-primary,
**158** for anything aid-conditional.

## Outstanding

1. **CRS pull** for sector detail (`source_table = "crs"`), per the "both" decision.
   Not blocking — DAC3A already supplies commitments.
2. **UNSC second source + 15 hand-checked terms.** The roster is still ONE
   source where the request requires two reconciled. This is the only remaining
   *requirement* rather than an enhancement.
3. ~~Refresh the votes extract to deposit v38.0~~ — **CLOSED, not possible.**
   `UNVotes` was removed from the deposit after v33.0; v34–v39 ship no roll-call
   file, and no replacement deposit exists. v33.0 is already what we hold. The
   investigation did surface the broken `year` column (above), which recovered
   5 events at +5; that fix is applied.

## Pipeline

```bash
Rscript src/r/data_prep_modules/unga/99_create_final_dataset.R   # 2.1 + 2.2
python  src/python/unsc_membership/parse_wikipedia_unsc.py       # 2.3 parse
Rscript src/r/data_prep_modules/unsc/99_create_final_dataset.R   # 2.3 build
Rscript src/r/data_prep_modules/unsc/98_task0_gate.R             # §4 criteria 1, 2, 2b, 4a
```
