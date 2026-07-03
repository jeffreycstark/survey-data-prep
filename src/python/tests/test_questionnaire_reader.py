"""Phase 6 tests: questionnaire reader + tri-source cross-validation.

Includes the plan's seeded-discrepancy fixture: a synthetic key where B and
C agree but A points the other way MUST yield A_vs_BC_conflict (the silent
mis-harmonization signature).

Run: uv run pytest src/python/tests/ -q
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from questionnaire_reader.crossvalidate.polarity import (  # noqa: E402
    classify_label,
    parse_response_scale,
    pole_end,
)
from questionnaire_reader.crossvalidate.tri_source import (  # noqa: E402
    Signature,
    _verdict,
)


# ---------------------------------------------------------------------------
# Polarity classification — parity with the R lexicon tests.
# ---------------------------------------------------------------------------
def test_classify_en_poles() -> None:
    assert classify_label("Strongly agree") == "pos"
    assert classify_label("Strongly disagree") == "neg"
    assert classify_label("neither agree nor disagree") == "unknown"
    assert classify_label("Hardly any confidence") == "neg"
    assert classify_label("Very strong") == "pos"


def test_classify_missing_normalization() -> None:
    # Apostrophe + slash normalization: the two bugs found live in Phase 6.
    assert classify_label("Don't know") == "missing"
    assert classify_label("Don’t know") == "missing"  # curly apostrophe
    assert classify_label("n/a") == "missing"
    assert classify_label("DK") == "missing"
    assert classify_label("IAP") == "missing"


def test_classify_ko_poles() -> None:
    assert classify_label("매우 그렇다") == "pos"
    assert classify_label("전혀 그렇지 않다") == "neg"
    assert classify_label("매우 불만족한다") == "neg"  # 불만족 disjoint from 만족
    assert classify_label("그저 그렇다") == "unknown"  # so-so midpoint
    assert classify_label("보통이다") == "unknown"
    assert classify_label("모르겠다") == "missing"
    assert classify_label("매우 노력한다") == "pos"  # tier-2 affirmative
    assert classify_label("전혀 노력하지 않는다") == "neg"  # tier-2 negation


# ---------------------------------------------------------------------------
# response_scale parsing (Source B).
# ---------------------------------------------------------------------------
def test_parse_response_scale_comma() -> None:
    sc = parse_response_scale(
        "1=Strongly agree, 2=Agree, 3=Disagree, 4=Strongly disagree"
    )
    assert sc is not None and len(sc) == 4
    assert sc[1.0] == "Strongly agree"


def test_parse_response_scale_space_separated() -> None:
    # KINU dictionary convention.
    sc = parse_response_scale(
        "1=very serious 2=somewhat serious 3=somewhat not serious "
        "4=not serious at all 9=n/a"
    )
    assert sc is not None and len(sc) == 5
    assert sc[4.0] == "not serious at all"
    assert sc[9.0] == "n/a"


def test_parse_response_scale_label_with_comma() -> None:
    sc = parse_response_scale("1=Yes, contacted them, 2=No, never")
    assert sc is not None
    assert sc[1.0] == "Yes, contacted them"
    assert sc[2.0] == "No, never"


def test_parse_response_scale_unparseable() -> None:
    assert parse_response_scale("open-ended verbatim response") is None
    assert parse_response_scale("") is None
    assert parse_response_scale(None) is None


# ---------------------------------------------------------------------------
# Pole-end reduction.
# ---------------------------------------------------------------------------
def test_pole_end_low_and_high() -> None:
    low = {1: "Strongly agree", 2: "Agree", 3: "Disagree", 4: "Strongly disagree"}
    assert pole_end(low) == ("low", "ok")
    high = {1: "Strongly disagree", 2: "Disagree", 3: "Agree", 4: "Strongly agree"}
    assert pole_end(high) == ("high", "ok")


def test_pole_end_unanchorable() -> None:
    assert pole_end({1: "Red", 2: "Blue"})[0] is None
    assert pole_end({1: "Agree"})[1] == "too_few_labels"
    interleaved = {1: "Agree", 2: "Disagree", 3: "Agree", 4: "Disagree"}
    assert pole_end(interleaved) == (None, "poles_overlap")


# ---------------------------------------------------------------------------
# Verdict engine — including the SEEDED DISCREPANCY.
# ---------------------------------------------------------------------------
def _sig(end: str | None, n: int = 4) -> Signature:
    return Signature(end=end, n_substantive=n, reason="ok" if end else "none")


def test_verdict_concordant() -> None:
    v, _ = _verdict(_sig("low"), _sig("low"), _sig("low"), b_usable=True)
    assert v == "concordant"


def test_verdict_seeded_a_vs_bc_conflict() -> None:
    # THE seeded discrepancy: raw .sav (A) says positive pole at LOW while
    # dictionary (B) and questionnaire originals (C) both say HIGH — the
    # silent mis-harmonization signature the auditor exists to catch.
    v, detail = _verdict(_sig("low"), _sig("high"), _sig("high"), b_usable=True)
    assert v == "A_vs_BC_conflict"
    assert "A=low" in detail and "B=high" in detail


def test_verdict_b_vs_c_conflict() -> None:
    v, _ = _verdict(None, _sig("low"), _sig("high"), b_usable=True)
    assert v == "B_vs_C_conflict"
    v2, _ = _verdict(_sig("low"), _sig("high"), _sig("low"), b_usable=True)
    assert v2 == "B_vs_C_conflict"


def test_verdict_cardinality_mismatch() -> None:
    v, detail = _verdict(_sig("low", 4), _sig("low", 5), None, b_usable=True)
    assert v == "cardinality_mismatch"
    assert "A=4" in detail and "B=5" in detail


def test_verdict_b_convention_gate() -> None:
    # With B excluded (intended-convention survey) only A remains -> no
    # comparison, never a false conflict from an intended-direction B.
    v, _ = _verdict(_sig("low"), _sig("high"), None, b_usable=False)
    assert v == "insufficient_evidence"


def test_verdict_insufficient() -> None:
    v, _ = _verdict(_sig("low"), None, None, b_usable=True)
    assert v == "insufficient_evidence"


# ---------------------------------------------------------------------------
# GCB end-to-end (integration; needs the repo's source documents).
# ---------------------------------------------------------------------------
def test_gcb_parse_integration() -> None:
    from questionnaire_reader.parsers.gcb import parse_gcb
    from questionnaire_reader.schema import COLUMNS, rows_to_frame

    rows = parse_gcb()
    assert len({r.raw_var for r in rows}) >= 90
    df = rows_to_frame(rows)
    assert list(df.columns) == COLUMNS
    q1a = df[df.raw_var == "Q1A"]
    assert set(q1a.response_code) >= {"0", "1", "2", "3", "99"}
    dk = q1a[q1a.response_code == "99"]
    assert bool(dk.missing_code_flag.iloc[0])  # Don't know flagged missing
