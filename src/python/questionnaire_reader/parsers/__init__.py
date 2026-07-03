"""Per-survey questionnaire-document parsers.

Each parser returns list[CodebookRow]; the registry maps survey slug to
parser callable. HWP-based Korean surveys are deferred (Phase 6 plan) —
their existing .txt extractions + verbatim CSVs carry Source B/C duty.
"""

from __future__ import annotations

from collections.abc import Callable

from ..schema import CodebookRow
from .afro import parse_afro
from .gcb import parse_gcb
from .lbs import parse_lbs

SURVEY_PARSERS: dict[str, Callable[[], list[CodebookRow]]] = {
    "gcb": parse_gcb,
    "lbs": parse_lbs,
    "afro": parse_afro,
}
