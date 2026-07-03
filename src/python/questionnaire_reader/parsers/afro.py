"""Afrobarometer parser — per-round merged-codebook PDFs.

The Afro codebooks are key-value blocks:

    Question Number: Q13
    Question: ... did you vote, or not ...
    Variable Label: Q13. Voting in the last national election
    Values: 0-3, 8, 9, -1
    Value Labels: 0=I did not vote, 1=I was too young ..., 9=Don't know

Value Labels frequently wrap across lines; the block's text is joined
before the 'code=' anchor-slicing parse (same parser as Source B).

Wave keys: w<N>, matching the afro spec's source: keys.
"""

from __future__ import annotations

import re
from pathlib import Path

from ..crossvalidate.polarity import classify_label, parse_response_scale
from ..paths import repo_root
from ..schema import CodebookRow

_QNUM = re.compile(r"^Question Number:\s*(\S+)", re.MULTILINE)
_FIELD = re.compile(
    r"^(Question|Variable Label|Values|Value Labels|Note|Source)\s*:", re.MULTILINE
)


def _find_codebook(round_dir: Path) -> Path | None:
    hits = sorted(round_dir.glob("*[Cc]odebook*.pdf"))
    return hits[0] if hits else None


def _block_fields(block: str) -> dict[str, str]:
    """Split one question block into its labelled fields (values joined)."""
    fields: dict[str, str] = {}
    matches = list(_FIELD.finditer(block))
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(block)
        key = m.group(1)
        val = block[m.end() : end]
        fields[key] = " ".join(val.split())
    return fields


def _parse_round(text: str, wave: str, source_doc: str) -> list[CodebookRow]:
    rows: list[CodebookRow] = []
    anchors = list(_QNUM.finditer(text))
    for i, m in enumerate(anchors):
        end = anchors[i + 1].start() if i + 1 < len(anchors) else len(text)
        raw_var = m.group(1).rstrip(".")
        fields = _block_fields(text[m.end() : end])
        scale = parse_response_scale(fields.get("Value Labels", ""))
        if scale is None:
            continue
        question = fields.get("Question", "") or fields.get("Variable Label", "")
        for code, label in scale.items():
            code_str = str(int(code)) if code == int(code) else str(code)
            rows.append(
                CodebookRow(
                    survey="afro",
                    wave=wave,
                    raw_var=raw_var,
                    question_text=question,
                    response_code=code_str,
                    response_label=label,
                    missing_code_flag=(
                        code < 0 or classify_label(label) == "missing"
                    ),
                    source_doc=source_doc,
                    language="en",
                    parse_confidence=0.85,
                    parse_method="pdf_kv_blocks",
                )
            )
    return rows


def parse_afro() -> list[CodebookRow]:
    root = repo_root()
    raw = root / "data" / "afro" / "raw"
    rows: list[CodebookRow] = []
    for round_dir in sorted(raw.glob("round[0-9]*")):
        n = re.sub(r"[^0-9]", "", round_dir.name)
        pdf = _find_codebook(round_dir)
        if pdf is None:
            continue
        from .pdf_common import pdf_to_text

        text = pdf_to_text(pdf)
        if text is None:
            continue
        rows.extend(
            _parse_round(
                text, wave=f"w{n}", source_doc=str(pdf.relative_to(root))
            )
        )
    return rows
