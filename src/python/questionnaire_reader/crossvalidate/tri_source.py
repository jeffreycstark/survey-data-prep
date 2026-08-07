"""Tri-source polarity cross-validation.

Reduces each source to a polarity signature per (wave, raw_var) —
(positive-pole end, substantive-code count) — and compares:

  A — data/<survey>/codebook/*.parquet          (R extractors; raw .sav truth)
  B — <survey>_verbatim_items.csv response_scale (hand-curated dictionary)
  C — <survey>_questionnaire_items.parquet       (this package's parses)

Verdicts (only keys with >=2 usable sources are emitted):
  concordant           all usable ends agree, cardinalities agree
  A_vs_BC_conflict     B and C agree, A differs — the classic silent
                       mis-harmonization signature
  B_vs_C_conflict      originals contradict the dictionary (stale dictionary)
  A_vs_B_conflict / A_vs_C_conflict   pairwise, when only two usable
  cardinality_mismatch ends agree but substantive-code counts differ

B-CONVENTION GATE (empirical, Phase 4): what response_scale documents
varies by survey. Surveys verified to record the INTENDED post-
harmonization direction (abs) have B excluded from the raw-frame verdict —
its conflicts with A/C are expected on every correctly-reversed item.
raw-verified (kgss, lbs) and no-reversal (gcb) surveys participate fully;
unknown surveys participate with b_convention="unknown" so results double
as a convention probe.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import pandas as pd
import yaml

from ..paths import codebook_parquets, parsed_dir, repo_root, verbatim_csv
from .polarity import classify_label, parse_response_scale, pole_end

# Verified in Phase 4 (see .VERBATIM_DECLARED_SURVEYS in
# 04_label_reconciliation.R). gcb = "raw" because its harmonization has no
# reversals, so raw == intended and either frame is comparable.
B_CONVENTION: dict[str, str] = {
    "abs": "intended",
    "kgss": "raw",
    "lbs": "raw",
    "gcb": "raw",
}


def _wave_digits(x: str) -> str:
    d = re.sub(r"[^0-9]", "", str(x).lower())
    return d if d else str(x).lower()


@dataclass
class Signature:
    end: str | None
    n_substantive: int
    reason: str


def _sig_from_codebook_rows(grp: pd.DataFrame) -> Signature:
    """Signature from codebook-v1 rows (Sources A and C)."""
    scale: dict[float, str] = {}
    n_sub = 0
    for _, row in grp.iterrows():
        try:
            code = float(row["response_code"])
        except (TypeError, ValueError):
            continue
        label = str(row["response_label"])
        flagged = bool(row["missing_code_flag"])
        if not flagged:
            n_sub += 1
            scale[code] = label
    end, reason = pole_end(scale)
    return Signature(end=end, n_substantive=n_sub, reason=reason)


def _sig_from_response_scale(text: str) -> Signature:
    """Signature from a verbatim response_scale string (Source B)."""
    scale = parse_response_scale(text)
    if scale is None:
        return Signature(end=None, n_substantive=0, reason="unparseable")
    sub = {c: lab for c, lab in scale.items() if classify_label(lab) != "missing"}
    end, reason = pole_end(sub)
    return Signature(end=end, n_substantive=len(sub), reason=reason)


def _load_a(survey: str) -> dict[tuple[str, str], Signature]:
    sigs: dict[tuple[str, str], Signature] = {}
    for p in codebook_parquets(survey):
        df = pd.read_parquet(p)
        for (wave, raw_var), grp in df.groupby(["wave", "raw_var"]):
            key = (_wave_digits(str(wave)), str(raw_var).upper())
            sigs[key] = _sig_from_codebook_rows(grp)
    return sigs


_EXCLUDE_SPEC = ("TEMPLATE", "README", "MODEL_VARIABLE")


def _yaml_source_bridge(survey: str) -> dict[tuple[str, str], str]:
    """(wave_digits, HARMONIZED_NAME) -> RAW_VAR from the YAML specs.

    The verbatim CSV's question_id frame does not always match the .sav
    variable names (KINU documents per-wave questionnaire codes while the
    pooled _en.sav uses its own names). The harmonization YAMLs' `source:`
    maps are the authoritative bridge.
    """
    cfg = repo_root() / "src" / "config" / survey
    spec_dir = cfg / "harmonize"
    if not spec_dir.is_dir():
        spec_dir = cfg / "harmonize"
    out: dict[tuple[str, str], str] = {}
    if not spec_dir.is_dir():
        return out
    for p in sorted(spec_dir.glob("*.yml")):
        if any(tok in p.name.upper() for tok in _EXCLUDE_SPEC):
            continue
        try:
            spec = yaml.safe_load(p.read_text(encoding="utf-8"))
        except yaml.YAMLError:
            continue
        for v in (spec or {}).get("variables") or []:
            vid = v.get("id")
            for wave, raw in (v.get("source") or {}).items():
                if vid and raw:
                    out[(_wave_digits(str(wave)), str(vid).upper())] = str(
                        raw
                    ).upper()
    return out


def _load_b(
    survey: str,
) -> tuple[dict[tuple[str, str], Signature], dict[tuple[str, str], str]]:
    """Signatures + (key -> harmonized_name) bridge from the verbatim CSV.

    Each dictionary row is keyed under BOTH its own question_id and the
    YAML `source:` raw_var for (harmonized_name, wave) — whichever frame
    Sources A/C use, the row is joinable.
    """
    sigs: dict[tuple[str, str], Signature] = {}
    bridge: dict[tuple[str, str], str] = {}
    path = verbatim_csv(survey)
    if path is None:
        return sigs, bridge
    yaml_bridge = _yaml_source_bridge(survey)
    df = pd.read_csv(path, dtype=str).fillna("")
    for _, row in df.iterrows():
        wave_d = _wave_digits(row["wave"])
        hname = str(row.get("harmonized_name", "")).strip()
        keys: list[tuple[str, str]] = []
        qid = str(row.get("question_id", "")).strip()
        if qid:
            keys.append((wave_d, qid.upper()))
        yaml_raw = yaml_bridge.get((wave_d, hname.upper())) if hname else None
        if yaml_raw:
            keys.append((wave_d, yaml_raw))
        sig: Signature | None = None
        for key in keys:
            if key in sigs:
                continue
            if sig is None:
                sig = _sig_from_response_scale(row.get("response_scale", ""))
            sigs[key] = sig
            bridge[key] = hname
    return sigs, bridge


def _load_c(survey: str) -> dict[tuple[str, str], Signature]:
    sigs: dict[tuple[str, str], Signature] = {}
    p = parsed_dir(survey) / f"{survey.replace('-', '_')}_questionnaire_items.parquet"
    if not p.is_file():
        return sigs
    df = pd.read_parquet(p)
    for (wave, raw_var), grp in df.groupby(["wave", "raw_var"]):
        key = (_wave_digits(str(wave)), str(raw_var).upper())
        sigs[key] = _sig_from_codebook_rows(grp)
    return sigs


def _verdict(
    a: Signature | None, b: Signature | None, c: Signature | None, b_usable: bool
) -> tuple[str, str]:
    ends: dict[str, str] = {}
    if a is not None and a.end is not None:
        ends["A"] = a.end
    if b_usable and b is not None and b.end is not None:
        ends["B"] = b.end
    if c is not None and c.end is not None:
        ends["C"] = c.end

    if len(ends) < 2:
        return "insufficient_evidence", f"usable_sources={len(ends)}"

    if len(set(ends.values())) == 1:
        ns = {
            k: s.n_substantive
            for k, s in (("A", a), ("B", b), ("C", c))
            if k in ends and s is not None
        }
        if len(set(ns.values())) > 1:
            detail = ",".join(f"{k}={v}" for k, v in sorted(ns.items()))
            return "cardinality_mismatch", detail
        return "concordant", ",".join(f"{k}={v}" for k, v in sorted(ends.items()))

    detail = ",".join(f"{k}={v}" for k, v in sorted(ends.items()))
    if "A" in ends and "B" in ends and "C" in ends:
        if ends["B"] == ends["C"] != ends["A"]:
            return "A_vs_BC_conflict", detail
        if ends["B"] != ends["C"]:
            return "B_vs_C_conflict", detail
        return "A_vs_BC_conflict", detail  # A agrees with one, not both: A odd one out
    if set(ends) == {"B", "C"}:
        return "B_vs_C_conflict", detail
    if set(ends) == {"A", "B"}:
        return "A_vs_B_conflict", detail
    return "A_vs_C_conflict", detail


def crossvalidate_survey(survey: str) -> Path:
    """Run the tri-source comparison; write + return the discrepancies CSV."""
    a_sigs = _load_a(survey)
    b_sigs, bridge = _load_b(survey)
    c_sigs = _load_c(survey)
    convention = B_CONVENTION.get(survey, "unknown")
    b_usable = convention != "intended"

    keys = set(a_sigs) | set(b_sigs) | set(c_sigs)
    rows = []
    for key in sorted(keys):
        a, b, c = a_sigs.get(key), b_sigs.get(key), c_sigs.get(key)
        n_present = sum(
            1
            for s, usable in ((a, True), (b, b_usable), (c, True))
            if s is not None and s.end is not None and usable
        )
        if n_present < 2:
            continue  # nothing to compare; tallied in the printed summary
        verdict, detail = _verdict(a, b, c, b_usable)
        rows.append(
            {
                "survey": survey,
                "wave_key": key[0],
                "raw_var": key[1],
                "harmonized_name": bridge.get(key, ""),
                "a_end": a.end if a else None,
                "b_end": b.end if b else None,
                "c_end": c.end if c else None,
                "a_n": a.n_substantive if a else None,
                "b_n": b.n_substantive if b else None,
                "c_n": c.n_substantive if c else None,
                "b_convention": convention,
                "verdict": verdict,
                "detail": detail,
            }
        )

    out = pd.DataFrame(rows)
    out_path = (
        parsed_dir(survey) / f"{survey.replace('-', '_')}_source_discrepancies.csv"
    )
    out.to_csv(out_path, index=False)

    counts = out["verdict"].value_counts().to_dict() if len(out) else {}
    print(
        f"[crossvalidate] {survey}: A={len(a_sigs)} B={len(b_sigs)} "
        f"C={len(c_sigs)} signature keys; compared={len(out)} "
        f"(b_convention={convention}, B {'included' if b_usable else 'EXCLUDED'})"
    )
    print(f"[crossvalidate] verdicts: {counts}")
    conflicts = (
        out[out["verdict"].str.contains("conflict")] if len(out) else pd.DataFrame()
    )
    if len(conflicts):
        print(conflicts.to_string(index=False, max_colwidth=30))
    print(f"[crossvalidate] CSV: {out_path}")
    return out_path
