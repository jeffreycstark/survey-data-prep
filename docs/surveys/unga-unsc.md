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

Ideal points are v38.0; votes are v33.0. That is why coverage ends **2025** for
one and **2022** for the other — it is a version skew, not a property of the
underlying data. It costs the paper's second outcome about 32 events (below).
**Refreshing the votes extract to v38.0 would likely close the gap** and is the
single cheapest available power gain.

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
| +5 | 253 | **220** | −33 |
| +10 | 227 | **195** | −32 |

Both still clear the gate. But **if the two outcomes are co-primary the binding N
is the smaller figure**, and the headline should not be 227. See the version-skew
note above — this gap is closable.

### Criterion 4, partially answered

Every UNSC term's `country_text_id` resolves in the ideal-point file — **zero
unmatched**. This is what licenses reading 253/227 as real rather than as
crosswalk attrition, which is the failure mode §3 warns about. The **full**
crosswalk still has to reconcile OECD DAC codes and is outstanding.

---

## Outstanding

1. **Deliverable 2.4 — bilateral aid.** Not built. Blocked on a decision that is
   Jeff's, not this repo's: **DAC Table 2a vs CRS** (§2.4 / §5). CRS disbursements
   are only reliably populated from ~2002 while the paper's universe opens in
   1970, so building from CRS would empty most of the panel for reasons that have
   nothing to do with the design. Table 2a runs from 1960 at the right
   granularity. The request explicitly says to flag this rather than switch
   tables silently.
2. **§3 country-code crosswalk** — `data/lookups/country_code_crosswalk.csv` not
   built. Needs COW ↔ ISO3 ↔ DAC ↔ V-Dem with year-validity ranges, and hand
   patches for the succession cases (USSR→RUS, YUG, CSK, DDR/DEU, YEM, SDN/SSD).
3. **UNSC second source + 15 hand-checked terms** (see above).
4. **Gate criterion 3** (aid coverage overlap) — blocked on item 1.

## Pipeline

```bash
Rscript src/r/data_prep_modules/unga/99_create_final_dataset.R   # 2.1 + 2.2
python  src/python/unsc_membership/parse_wikipedia_unsc.py       # 2.3 parse
Rscript src/r/data_prep_modules/unsc/99_create_final_dataset.R   # 2.3 build
Rscript src/r/data_prep_modules/unsc/98_task0_gate.R             # §4 criteria 1, 2, 2b, 4a
```
