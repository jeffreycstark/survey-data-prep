# Construct anchor files

This directory holds **anchor files**: hand-curated YAMLs that declare, per construct, which variables are expected to load on a single anchor item and in which direction. The Layer 4 audit diagnostic (`src/r/audit/04_anchor_diagnostic.R`, ticket D3) consumes these files to mechanically verify that every YAML's reverse-coding decision produced a variable whose correlation with the anchor matches theory.

See `audit/01-audit-framework.md` §Layer 4 for the framework rationale; `audit/02-implementation-tickets.md` Phase D for the ticket sequence.

---

## What is an anchor file?

The "silent killer" pattern in this repo is `safe_reverse_4pt` (or any `safe_reverse_*pt`) running on a variable whose true direction nobody verified. The engine reverses unconditionally; the harmonized output looks plausible; downstream analyses report wrong-signed coefficients with no warning. Layer 1 (schema) cannot catch this — the YAML is internally consistent. Layer 3 (output invariants) cannot catch it — the values are inside `valid_range`.

The only mechanism that catches it is **anchor correlation**: pick one variable per construct whose direction is known and stable (the *anchor*), declare every other variable's expected sign of correlation with that anchor, and verify the observed correlations match. A reverse-coding mistake flips the observed sign and fails the check.

An anchor file is the YAML that declares one such (anchor, loaders, expected signs) bundle. It is the minimum-viable mechanical check that a variable's direction is what the YAML claims.

---

## Schema reference

Schema: `src/config/_anchors/_schema/anchor_v1.schema.json` (JSON Schema draft-07, AJV-compatible). `additionalProperties: false` everywhere — typos fail loud.

Top-level fields:

| Field | Required | Description |
|---|---|---|
| `schema_version` | yes | Must be the integer `1`. |
| `construct` | yes | Snake-case construct name (e.g. `democratic_attitudes`). |
| `description` | no | Free-text paragraph describing what the construct is and why these loaders cohere. |
| `notes` | no | String or list of strings; freeform. |
| `last_reviewed` | no | ISO date `YYYY-MM-DD` of the last human review of `expected_sign` assignments. |
| `anchor` | yes | The anchor variable block (see below). |
| `loaders` | yes | Array of loader objects (see below); ≥ 1. |

`anchor` block:

| Field | Required | Description |
|---|---|---|
| `variable` | yes | Snake-case `id:` of the anchor variable, matching some YAML's `id:`. |
| `expected_direction` | yes | `positive` (higher = more of construct), `negative`, or `none`. |
| `per_wave` | no | Map wave-key → direction; per-wave overrides for waves where the anchor itself reverses. |
| `notes` | no | Freeform. |

`loaders[].` (each loader):

| Field | Required | Description |
|---|---|---|
| `id` | yes | Snake-case variable id, matching a YAML `id:`. |
| `expected_sign` | yes | `positive`, `negative`, or `either` (only for genuinely ambivalent items). |
| `justification` | yes | 10–500 chars; one-sentence substantive reason. |
| `min_correlation` | no | Floor for "weak loader" warning; default 0.05 in diagnostic. |
| `surveys` | no | Restrict loader to listed surveys (array of survey-name strings). |
| `waves` | no | Restrict loader to listed wave keys. |
| `notes` | no | Freeform. |

---

## How to author an anchor file

Six-step procedure:

1. **Pick a construct.** Name a coherent latent dimension (`democratic_attitudes`, `institutional_trust`, `economic_evaluations`, `authoritarianism`). One construct = one file.

2. **Identify the anchor variable.** Criteria:
   - Stable direction across all waves of every survey it appears in (or per-wave overrides documented in `anchor.per_wave`).
   - Well-known loading in the substantive literature.
   - Already declared as an `id:` in some harmonization YAML — the diagnostic reads it from harmonized output, not from raw data.
   - Prefer items with high response rates and good cross-cultural validity.

3. **Enumerate candidate loaders.** Grep `id:` across the relevant surveys' YAMLs:
   ```bash
   grep -rh "^  - id:" src/config/abs/harmonize_validated/ \
     | sort -u
   ```
   Pick the items that substantive theory predicts should covary with the anchor. Aim for 5–15 loaders per construct; fewer leaves the anchor unstressed, more invites mixed signals.

4. **Write a one-sentence justification per loader.** Cite literature (e.g. "Mishler & Rose 2001 — democratic-performance evaluation cluster") OR cite codebook semantics ("question wording asks 'how satisfied' — same response frame as anchor"). The schema requires 10–500 chars, but the substantive standard is higher: a reviewer should be able to read your justification and either nod or push back. "They're related" is rejected on review even though the schema accepts it.

5. **Assign `expected_sign` from theory.** Default to the theory's prediction. If theory genuinely does not commit (the item is ambivalent or multi-dimensional), use `either` and explain in the justification why. `either` is a real signal to the diagnostic: it suppresses the sign-disagreement error but still records the observed sign for human review.

6. **Run the diagnostic to verify the file works.** Once D3 lands:
   ```bash
   Rscript src/r/audit/04_anchor_diagnostic.R --survey abs --construct authoritarianism
   ```
   Errors fall into three buckets — see the *Authoring constraints* section below.

---

## Sample anchor file

A complete realistic anchor for `authoritarianism`. The four ABS authoritarian-rule items (`strongman_rule`, `single_party_rule`, `military_rule`, `expert_rule`) are a battery: respondents are asked separately whether each form of non-democratic rule would be a good thing. Theory predicts they cluster — the four-item battery is treated as a single latent authoritarian-preference dimension in much of the comparative-democratization literature (e.g. Norris 2011; Welzel 2013). One serves as the anchor, the others as loaders, all `positive` because they all measure the same direction.

```yaml
schema_version: 1
construct: authoritarianism
description: >
  Cross-survey cluster of regime-preference items asking whether non-democratic
  forms of rule (strongman, single-party, military, expert/technocratic) would
  be a good thing. Loaders are the three remaining items in the ABS battery,
  all coded with `positive` expected sign because they all run higher = more
  authoritarian after harmonization.
last_reviewed: 2026-05-09

anchor:
  variable: strongman_rule
  expected_direction: positive
  notes: >
    Strongman rule is the canonical anchor for authoritarian regime preference.
    All ABS waves W1-W6 use the same response frame after harmonization
    (1 = very bad, 4 = very good). No per_wave override needed.

loaders:
  - id: single_party_rule
    expected_sign: positive
    justification: >
      Single-party rule clusters with strong-leader preference as a coherent
      regime-preference dimension (Norris 2011, ch. 6).
  - id: military_rule
    expected_sign: positive
    justification: >
      Military rule is the most assertive form of non-democratic preference;
      correlates strongly with strongman support across ABS waves (Chu et al.
      2008).
  - id: expert_rule
    expected_sign: positive
    justification: >
      Technocratic/expert rule loads on the same dimension though more weakly;
      framed as 'experts decide rather than government' (Welzel 2013, ch. 4).
    min_correlation: 0.10
```

Design choices:
- **Anchor is `strongman_rule`** because it has the most direct one-question framing and the most coverage in the comparative literature. Any of the four would work; pick the one with the cleanest direction.
- **All loaders are `positive`** because the harmonization spec for `authoritarianism.yml` declares `Convention: HIGH = more authoritarian/anti-democratic` and reverse-codes accordingly. If a loader fails this check, that means either the YAML's reversal was wrong OR the substantive theory is wrong — the diagnostic surfaces it for adjudication.
- **`expert_rule` has `min_correlation: 0.10`** because the technocratic-rule item is theoretically expected to load more weakly than the other three (it taps a related but distinct dimension); raising the floor avoids a false-positive "weak loader" warning while keeping the sign check.
- **No `per_wave` block** because all six ABS waves use the same response frame after harmonization. If W1 had used a 5-point scale collapsed to 4, that would be a recoding decision invisible at the anchor-file layer — Layer 3 catches it, not Layer 4.

---

## What an anchor is NOT

- **Not a factor model.** The diagnostic computes pairwise Pearson correlations, not factor loadings. If the construct has multiple latent dimensions, that's a separate conversation; the anchor file is the minimum-viable check that *direction* is right.
- **Not a proxy for construct validity.** Construct-validity work (CFA, IRT, measurement-equivalence tests) belongs in papers, not in the audit. The anchor only tests the much weaker claim "the sign of the correlation should be X."
- **Not a substitute for Layer 1, 2, or 3.** Layer 1 (schema) catches typos. Layer 2 (codebook reconciliation) catches "the YAML claims this item is on a 1–4 scale but the .sav says 1–5." Layer 3 (output invariants) catches range violations. Layer 4 only catches direction errors. The four layers compose.

---

## Cross-survey constructs

A construct like `institutional_trust` spans ABS (`trust_*` variables), KGSS (`conf_*`), KAMOS, and KINU. Two valid patterns:

**Pattern A — one anchor file per survey.** `institutional_trust_abs.yml`, `institutional_trust_kgss.yml`, etc. Use when surveys define the construct differently (different anchor, different loaders, different scale conventions). Each file is independent.

**Pattern B — one anchor file with `surveys:` per loader.** `institutional_trust.yml` with the anchor variable common to all relevant surveys, and each loader's `surveys:` field restricting it to where it exists. Use when the anchor is shared and the construct's theoretical structure is the same across surveys.

```yaml
schema_version: 1
construct: institutional_trust
anchor:
  variable: trust_government
  expected_direction: positive
loaders:
  - id: trust_parliament
    expected_sign: positive
    surveys: [abs, wvs, lbs, afro, kgss]
    justification: "Trust in parliament loads with trust in government as the elected-branch dimension of institutional trust (Newton & Norris 2000)."
  - id: conf_judiciary
    expected_sign: positive
    surveys: [kgss]
    justification: "KGSS conf_judiciary asks confidence in the judiciary on a 1-3 scale; expected to load with government trust as a regime-institutional cluster."
```

The diagnostic respects `surveys:` — when run with `--survey kgss`, it skips loaders whose `surveys:` doesn't include `kgss`. (D2/D3 owners: please confirm the diagnostic reports loaders skipped due to `surveys:` mismatch alongside loaders skipped because the variable wasn't found in the harmonized output, so the user can distinguish "intentionally excluded" from "expected but missing.")

---

## Wave-direction flips

Sometimes the anchor itself reverses direction across waves — the question was rephrased, or the response options were re-ordered. Declare per-wave overrides in `anchor.per_wave`:

```yaml
anchor:
  variable: dem_sat_national
  expected_direction: positive
  per_wave:
    w2: negative
  notes: >
    W2 used 'satisfied with the central government' with reversed response
    options (1 = very satisfied → 4 = not at all). Harmonization preserves the
    raw direction; the anchor file declares the W2 sign so loaders are not
    spuriously flagged for that wave.
```

The diagnostic interprets each loader's `expected_sign` *relative to the anchor's direction in that wave*. So a loader with `expected_sign: positive` and a W2 anchor with `expected_direction: negative` is expected to have a *negative* observed correlation in W2 (positive · negative = negative).

If the loader itself flips wave-to-wave (separate from the anchor), that is a Layer 4 finding — declare it explicitly in the harmonization YAML's `qc.wave_direction_flip` (ticket D7) rather than in the anchor file.

---

## Authoring constraints

When the diagnostic flags a loader you justified, you have three options. Don't suppress the warning without picking one:

1. **The YAML is wrong.** The reverse-coding decision was incorrect (forgot to reverse, reversed when shouldn't have, applied the wrong wave-rule). Fix the YAML. Re-run the diagnostic.
2. **The anchor file's `expected_sign` is wrong.** Theory says one thing, but on closer reading the loader is genuinely ambivalent or measures a different dimension than the anchor. Edit the anchor file — change `positive` to `either`, or move the loader to a different construct.
3. **The empirical pattern in this dataset genuinely contradicts theory.** This is the rarest and most interesting case. Document it: add a `notes:` field to the loader explaining the contradiction, set `expected_sign: either` to suppress the error, and consider whether it's worth a paper.

Other constraints:

- **Justifications must be substantive.** "Strong-leader rule should anti-correlate with satisfaction with how democracy works because both tap regime preference" is acceptable. "They're related" is not. The schema enforces a 10-character floor; the review standard is higher.
- **Default `expected_sign` is theory's prediction.** Use `either` only when theory is genuinely silent, and say so in the justification ("the literature is split on whether this item taps the same dimension as the anchor").
- **One construct per file.** Don't combine `democratic_attitudes` and `authoritarianism` even though they're substantively linked — separate anchors keep the diagnostic interpretable.
- **Anchor's `id:` must exist.** The diagnostic reads anchor and loader values from the harmonized output. If `anchor.variable` is not declared as an `id:` in any YAML for the survey under audit, the diagnostic should report an "unresolvable anchor" error rather than silently drop the construct.
