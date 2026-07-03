"""Bilingual polarity classification — Python mirror of the R lexicon.

Loads src/config/_audit/polarity_lexicon.yml (the SYNC CONTRACT twin of
default_polarity_lexicon() in src/r/audit/04_label_reconciliation.R) and
reproduces its semantics exactly:

  - missing patterns win first;
  - a label is pos/neg when >=1 family matches that pole and none matches
    the opposite (pos+neg contradiction -> unknown, protecting midpoints);
  - tier-2 generic Korean morphology applies only when NO family matched,
    with negation (지 않) decisive over the intensifier+predicate
    affirmative.

pole_end() then reduces a code->label scale to which END holds the
positive pole ("low"/"high"/None) — the polarity signature used by the
tri-source cross-validation.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import lru_cache

import yaml

from ..paths import polarity_lexicon_path

Patterns = tuple[re.Pattern[str], ...]


@dataclass(frozen=True)
class Lexicon:
    missing: Patterns
    families: tuple[tuple[Patterns, Patterns], ...]
    ko_pos: Patterns
    ko_neg: Patterns


def _compile(patterns: list[str]) -> tuple[re.Pattern[str], ...]:
    return tuple(re.compile(p) for p in patterns)


@lru_cache(maxsize=1)
def load_lexicon() -> Lexicon:
    raw = yaml.safe_load(polarity_lexicon_path().read_text(encoding="utf-8"))
    families = tuple(
        (_compile(fam["pos"]), _compile(fam["neg"]))
        for fam in raw["families"].values()
    )
    return Lexicon(
        missing=_compile(raw["missing_patterns"]),
        families=families,
        ko_pos=_compile(raw["ko_generic"]["pos"]),
        ko_neg=_compile(raw["ko_generic"]["neg"]),
    )


def _norm(label: str) -> str:
    s = str(label).lower()
    # Apostrophes are DELETED (not spaced) so "don't/don’t know" collapses to
    # "dont know", which the lexicon's "don'?t know" patterns match.
    s = re.sub(r"['’`]", "", s)
    s = re.sub(r"[^\w\s]", " ", s)  # other punctuation -> space (keeps Hangul)
    return " ".join(s.split())


def _any(s: str, pats: tuple[re.Pattern[str], ...]) -> bool:
    return any(p.search(s) for p in pats)


def classify_label(label: str) -> str:
    """'pos' | 'neg' | 'missing' | 'unknown' — mirrors R classify_pole()."""
    lex = load_lexicon()
    s = _norm(label)
    if not s:
        return "unknown"
    if _any(s, lex.missing):
        return "missing"
    hit_pos = any(_any(s, pos) for pos, _ in lex.families)
    hit_neg = any(_any(s, neg) for _, neg in lex.families)
    if hit_pos and not hit_neg:
        return "pos"
    if hit_neg and not hit_pos:
        return "neg"
    if hit_pos and hit_neg:
        return "unknown"  # contradiction — stop here
    # Tier 2: generic Korean morphology; negation decisive.
    if _any(s, lex.ko_neg):
        return "neg"
    if _any(s, lex.ko_pos):
        return "pos"
    return "unknown"


def pole_end(scale: dict[float, str]) -> tuple[str | None, str]:
    """Which end of a code->label scale holds the positive pole.

    Returns ("low"|"high"|None, reason). Mirrors R find_pole_end(): both
    poles must classify and must not interleave.
    """
    if len(scale) < 2:
        return None, "too_few_labels"
    pos_codes: list[float] = []
    neg_codes: list[float] = []
    for code, label in scale.items():
        cls = classify_label(label)
        if cls == "pos":
            pos_codes.append(code)
        elif cls == "neg":
            neg_codes.append(code)
    if not pos_codes or not neg_codes:
        return None, "no_classifiable_poles"
    if max(pos_codes) < min(neg_codes):
        return "low", "ok"
    if min(pos_codes) > max(neg_codes):
        return "high", "ok"
    return None, "poles_overlap"


def substantive_codes(scale: dict[float, str]) -> list[float]:
    """Codes whose labels are not missing-classified (cardinality basis)."""
    return [c for c, lab in scale.items() if classify_label(lab) != "missing"]


_CODE_EQ = re.compile(r"(-?[0-9]+(?:\.[0-9]+)?)\s*=")


def parse_response_scale(text: str | None) -> dict[float, str] | None:
    """Parse a response_scale string into {code: label} (Source B).

    Labels are sliced between 'code=' anchors, so both comma-separated
    ('1=Strongly agree, 2=...') and space-separated ('1=18-29 2=30-39',
    the KINU dictionary convention) formats parse, and labels may contain
    commas. Needs >=2 entries, else None (no false anchor). Mirrors R
    .parse_response_scale() — SYNC CONTRACT.
    """
    if text is None or not str(text).strip():
        return None
    s = str(text)
    anchors = list(_CODE_EQ.finditer(s))
    if len(anchors) < 2:
        return None
    out: dict[float, str] = {}
    for i, m in enumerate(anchors):
        end = anchors[i + 1].start() if i + 1 < len(anchors) else len(s)
        label = s[m.end() : end].strip().rstrip(",;").strip()
        if label:
            out[float(m.group(1))] = label
    return out if len(out) >= 2 else None
