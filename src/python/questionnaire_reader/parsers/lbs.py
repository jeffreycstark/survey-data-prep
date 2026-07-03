"""LBS parser — per-year English codebook PDFs.

pdftotext -layout renders the LBS codebooks as regular blocks:

    P13ST.E   Confidence in the National Government
              1- A lot
              2- Some
              ...
              -1-- Don´t know

A block is accepted only when >=2 response lines parse (that filters page
headers, prose, and TOC noise); parse_confidence is 0.8 (pdf_layout) —
lower than the GCB xlsx because layout extraction can merge columns.

Wave keys: y<year>, matching the lbs spec's source: keys.
"""

from __future__ import annotations

import re
from pathlib import Path

from ..crossvalidate.polarity import classify_label
from ..paths import repo_root
from ..schema import CodebookRow

_VAR_LINE = re.compile(r"^([A-Z][A-Za-z0-9_.]{0,20})\s{2,}(\S.*)$")
_RESP_LINE = re.compile(r"^\s+(-?\d+)\s*-+\s*(\S.*)$")


def _find_codebook(year_dir: Path) -> Path | None:
    pats = ["*codebook*eng*.pdf", "*Codebook*Eng*.pdf", "*[Cc]odebook*.pdf"]
    for pat in pats:
        hits = sorted(year_dir.glob(pat))
        if hits:
            return hits[0]
    return None


def _parse_text(text: str, wave: str, source_doc: str) -> list[CodebookRow]:
    rows: list[CodebookRow] = []
    var: str | None = None
    question: str = ""
    scale: list[tuple[str, str]] = []

    def flush() -> None:
        nonlocal var, question, scale
        if var is not None and len(scale) >= 2:
            for code, label in scale:
                rows.append(
                    CodebookRow(
                        survey="lbs",
                        wave=wave,
                        raw_var=var,
                        question_text=question,
                        response_code=code,
                        response_label=label,
                        missing_code_flag=(
                            int(code) < 0 or classify_label(label) == "missing"
                        ),
                        source_doc=source_doc,
                        language="en",
                        parse_confidence=0.8,
                        parse_method="pdf_layout",
                    )
                )
        var, question, scale = None, "", []

    for line in text.splitlines():
        m_resp = _RESP_LINE.match(line)
        if m_resp and var is not None:
            scale.append((m_resp.group(1), m_resp.group(2).strip()))
            continue
        m_var = _VAR_LINE.match(line)
        if m_var:
            flush()
            var, question = m_var.group(1), m_var.group(2).strip()
            continue
        if var is not None and not scale and line.startswith(" ") and line.strip():
            question += " " + line.strip()  # wrapped question text
    flush()
    return rows


def parse_lbs() -> list[CodebookRow]:
    root = repo_root()
    raw = root / "data" / "lbs" / "raw"
    rows: list[CodebookRow] = []
    for year_dir in sorted(p for p in raw.iterdir() if p.is_dir()):
        if not re.fullmatch(r"\d{4}", year_dir.name):
            continue
        pdf = _find_codebook(year_dir)
        if pdf is None:
            continue
        from .pdf_common import pdf_to_text

        text = pdf_to_text(pdf)
        if text is None:
            continue
        rows.extend(
            _parse_text(
                text,
                wave=f"y{year_dir.name}",
                source_doc=str(pdf.relative_to(root)),
            )
        )
    return rows
