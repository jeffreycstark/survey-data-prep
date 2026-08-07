#!/usr/bin/env python3
"""
build_abs_verbatim.py

Builds abs_verbatim_items.csv by:
1. Parsing YAML harmonization configs to get (harmonized_name, wave, question_id)
2. Extracting verbatim text from official ABS questionnaire documents (DOCX/PDF)
3. Matching question IDs to verbatim text, sections, stems, and response scales

Output: data/abs/questionnaire_text/abs_verbatim_items.csv

Usage:
  cd /Users/jeffreystark/Development/Research/survey-data-prep
  python scripts/build_abs_verbatim.py
"""

import csv
import re
from pathlib import Path

import docx
import pdfplumber
import yaml


PROJECT_ROOT = Path(__file__).resolve().parent.parent
YAML_DIR = PROJECT_ROOT / "src" / "config" / "abs" / "harmonize"
OUTPUT_PATH = PROJECT_ROOT / "data" / "abs" / "questionnaire_text" / "abs_verbatim_items.csv"

WAVES = ["w1", "w2", "w3", "w4", "w5", "w6"]

QUESTIONNAIRE_FILES = {
    "w1": ("docx", PROJECT_ROOT / "data" / "abs" / "raw" / "wave1" / "CoreQs-May25rev.docx"),
    "w2": ("docx", PROJECT_ROOT / "data" / "abs" / "raw" / "wave2" / "ABS2_Core Questionnaire20170220.docx"),
    "w3": ("docx", PROJECT_ROOT / "data" / "abs" / "raw" / "wave3" / "ABSIII_1_Core Questionnaire.docx"),
    "w4": ("pdf", PROJECT_ROOT / "data" / "abs" / "raw" / "wave4" / "ABS4_Core_Questionnaire.pdf"),
    "w5": ("pdf", PROJECT_ROOT / "data" / "abs" / "raw" / "wave5" / "ABS5_Core_Questionnaire_20190805.pdf"),
    "w6": ("pdf", PROJECT_ROOT / "data" / "abs" / "raw" / "wave6" / "ABS6_Core_Questionnaire_final.pdf"),
}


# ── Step 1: Parse YAML configs ──────────────────────────────────────────────

def normalize_qid(qid: str) -> str:
    """Normalize question ID: q007 -> q7, Q7 -> q7."""
    qid = qid.strip().lower()
    m = re.match(r'^q0*(\d+)(.*)$', qid)
    if m:
        return f"q{int(m.group(1))}{m.group(2)}"
    return qid


def classify_qid(qid: str) -> str:
    """Classify a question ID into category: question, metadata, demographics, sub_item."""
    qid_lower = qid.lower()
    if qid_lower in ("country", "idnumber", "level", "level3", "month", "year", "w", "w_cross"):
        return "metadata"
    if re.match(r'^(se|ir|SE|IR)\d', qid):
        return "demographics"
    if re.match(r'^(allweight|couweight|weight)', qid_lower):
        return "metadata"
    if re.match(r'^q\d+[a-z]', qid_lower):
        return "sub_item"
    return "question"


def parse_yaml_lookup() -> list[dict]:
    """Parse all YAML files to build the lookup table."""
    entries = []
    for yml_path in sorted(YAML_DIR.glob("*.yml")):
        with open(yml_path, encoding="utf-8") as f:
            config = yaml.safe_load(f)
        if not config or "variables" not in config:
            continue
        yaml_file = yml_path.stem
        for var in config["variables"]:
            src = var.get("source", {})
            scale = var.get("scale", {})
            scale_labels = scale.get("labels", {})
            if scale_labels:
                scale_str = ", ".join(f"{k}={v}" for k, v in sorted(scale_labels.items()))
            else:
                scale_str = ""

            for wave in WAVES:
                qid_raw = src.get(wave)
                entries.append({
                    "harmonized_name": var["id"],
                    "wave": wave,
                    "question_id": str(qid_raw).strip() if qid_raw is not None else "",
                    "description": var.get("description", ""),
                    "concept": var.get("concept", yaml_file),
                    "yaml_file": yaml_file,
                    "scale_labels_yaml": scale_str,
                    "note_yaml": var.get("note", ""),
                })
    return entries


# ── Step 2: Extract text from questionnaire documents ────────────────────────

def extract_docx_lines(path: Path) -> list[str]:
    doc = docx.Document(str(path))
    return [p.text.strip() for p in doc.paragraphs if p.text.strip()]


def extract_pdf_lines(path: Path) -> list[str]:
    pdf = pdfplumber.open(str(path))
    lines = []
    for page in pdf.pages:
        text = page.extract_text()
        if text:
            for line in text.split("\n"):
                t = line.strip()
                if t:
                    lines.append(t)
    return lines


def extract_lines(wave: str) -> list[str]:
    fmt, path = QUESTIONNAIRE_FILES[wave]
    if not path.exists():
        print(f"  WARNING: {path} not found")
        return []
    if fmt == "docx":
        return extract_docx_lines(path)
    else:
        return extract_pdf_lines(path)


# ── Step 3: Parse questionnaire text ────────────────────────────────────────

# Formatting/instruction patterns to clean from item text
RE_SHOWCARD = re.compile(r'\(SHOWCARD\)', re.IGNORECASE)
RE_GBS = re.compile(r'【GBS】')
RE_OPTIONAL_TAG = re.compile(r'<\s*[Oo]ptional\s*>')
RE_NEW_REVISED = re.compile(r'\((NEW|REVISED)\)', re.IGNORECASE)
RE_DO_NOT_READ = re.compile(r'\(Do not read:.*?\)', re.IGNORECASE)


def clean_text(text: str) -> str:
    """Remove interviewer instructions and formatting markers."""
    text = RE_SHOWCARD.sub('', text)
    text = RE_GBS.sub('', text)
    text = RE_NEW_REVISED.sub('', text)
    text = RE_OPTIONAL_TAG.sub('', text)
    text = RE_DO_NOT_READ.sub('', text)
    # Clean up multiple spaces
    text = re.sub(r'\s+', ' ', text).strip()
    return text


def is_skip_line(line: str) -> bool:
    """Check if a line should be skipped (response codes, formatting, headers)."""
    # Pure numbers (response codes)
    if re.match(r'^[\d\s]+$', line) and len(line) < 30:
        return True
    # Column header abbreviations
    if re.match(r'^(SA|SWA|SWD|SD|DK|DNA|DAns|DU|CC|DA)$', line):
        return True
    # Response scale headers (table column labels)
    if re.match(r'^(A Great Deal|Quite a Lot|Not Very Much|None At All|'
                r'of Trust|Much Trust|Trust|Distrust|fully|somewh|at\b|'
                r'Do not|understa|nd\b|the\b|question|Can\'t|Decline|'
                r'Deal|Lot of)', line):
        return True
    # RING CARDS / SHOWCARD instruction lines (including PDF table headers)
    if re.match(r'^\(RING CARDS', line, re.IGNORECASE):
        return True
    if re.match(r'^\(SHOWCARD\)', line, re.IGNORECASE):
        return True
    # Qs. reference lines
    if re.match(r'^Qs?\.\s*\d+', line):
        return True
    # PDF table column header fragments (only when they appear as standalone short lines)
    if len(line) < 30 and re.match(
        r'^(fully|lot$|the$|question$|understand$|choose$|to answer$|nd$|at$)',
        line, re.IGNORECASE
    ):
        return True
    # Lines that are just "Decline to answer)" or continuation of do-not-read
    if re.match(r'^(Decline to answer\)?|Can.t choose)', line, re.IGNORECASE):
        return True
    # [Do not read] lines
    if line.startswith('[Do not read]') or line.startswith('[DO NOT READ]'):
        return True
    # Response option with tab+number
    if re.match(r'^.+\t\d+$', line):
        return True
    # Dotted response lines from PDFs: "Very good ........... 1"
    if re.match(r'^.+\.{3,}\s*\d+$', line):
        return True
    # Known response text patterns with trailing number
    response_starters = [
        r'^(Very good|Good|Bad|Very bad|So so)',
        r'^(Much better|A little better|About the same|A little worse|Much worse)',
        r'^(Very satisfied|Fairly satisfied|Not very satisfied|Not at all)',
        r'^(Strongly agree|Somewhat agree|Somewhat disagree|Strongly disagree)',
        r'^(A great deal|Quite a lot|Not very much|None at all)',
        r'^(Yes|No)\s+\d',
        r'^(Always|Often|Sometimes|Rarely|Never|Seldom)\s+\d',
        r'^(A lot|Somewhat|A little|Not at all)\s+\d',
    ]
    for pat in response_starters:
        if re.match(pat, line, re.IGNORECASE):
            return True
    return False


def is_section_header(line: str) -> bool:
    """Check if line is a section header like 'A. ECONOMIC EVALUATIONS'."""
    if re.match(r'^[A-Z]\.\s+[A-Z]', line):
        return True
    # All-caps substantive header (not a short abbreviation)
    if line.isupper() and len(line) > 5 and not re.match(r'^[\d\s]+$', line):
        return True
    return False


def parse_questionnaire(wave: str, lines: list[str]) -> dict:
    """Parse questionnaire lines into structured question data.

    Returns dict: {q_key: {section, stem_text, item_text, notes}}
    where q_key is normalized like 'q7', 'q8', etc.
    """
    questions = {}
    current_section = ""
    current_stem = ""
    current_battery_range = None  # (start, end)

    i = 0
    while i < len(lines):
        line = lines[i]

        # ── Section header ──
        if re.match(r'^[A-Z]\.\s+[A-Z]', line):
            current_section = line
            current_stem = ""
            current_battery_range = None
            i += 1
            continue

        # ── All-caps subsection (don't overwrite section) ──
        if is_section_header(line) and not re.match(r'^\d', line):
            i += 1
            continue

        # ── Battery range: "7-18." or "7-19" or "133-146." ──
        m_battery = re.match(r'^(\d+)\s*[-–]\s*(\d+)\.?\s*$', line)
        if m_battery:
            current_battery_range = (int(m_battery.group(1)), int(m_battery.group(2)))
            current_stem = _gather_stem(lines, i + 1, current_battery_range)
            i += 1
            # Skip ahead past stem lines — stop at question starts OR battery items
            while i < len(lines):
                if _is_question_start(lines[i]):
                    break
                if _is_bare_battery_number(lines[i], current_battery_range):
                    break
                if _is_pdf_battery_item(lines[i], current_battery_range):
                    break
                i += 1
            continue

        # ── Battery range with inline stem: "7-19 I'm going to name..." ──
        m_battery_stem = re.match(r'^(\d+)\s*[-–]\s*(\d+)\.?\s+(.+)$', line)
        if m_battery_stem:
            current_battery_range = (int(m_battery_stem.group(1)), int(m_battery_stem.group(2)))
            stem_start = m_battery_stem.group(3).strip()
            # Gather continuation of stem
            stem_parts = [stem_start]
            j = i + 1
            while j < len(lines) and len(stem_parts) < 5:
                next_line = lines[j].strip()
                if _is_question_start(next_line):
                    break
                if _is_bare_battery_number(next_line, current_battery_range):
                    break
                if _is_pdf_battery_item(next_line, current_battery_range):
                    break
                if is_skip_line(next_line):
                    j += 1
                    continue
                if is_section_header(next_line):
                    break
                stem_parts.append(next_line)
                j += 1
            current_stem = clean_text(" ".join(stem_parts))
            i = j
            continue

        # ── Paired question: "32/44." ──
        m_paired = re.match(r'^(\d+)/(\d+)\.\s*$', line)
        if m_paired:
            q1 = int(m_paired.group(1))
            q2 = int(m_paired.group(2))
            item_text = _gather_item_text(lines, i + 1)
            notes = ""
            if RE_OPTIONAL_TAG.search(item_text):
                notes = "Optional item"
                item_text = RE_OPTIONAL_TAG.sub('', item_text).strip()
            item_text = clean_text(item_text)
            for qn in [q1, q2]:
                questions[f"q{qn}"] = {
                    "section": current_section,
                    "stem_text": current_stem if current_battery_range and
                                 current_battery_range[0] <= qn <= current_battery_range[1] else "",
                    "item_text": item_text,
                    "notes": notes,
                }
            i += 1
            while i < len(lines) and not _is_question_start(lines[i]) and not is_section_header(lines[i]):
                i += 1
            continue

        # ── Question with period: "7. text" or "7." ──
        m_q = re.match(r'^(\d+)\.\s*(.*?)$', line)
        if m_q and not re.match(r'^\d+\.\d', line):  # exclude decimal numbers
            q_num = int(m_q.group(1))
            inline_text = m_q.group(2).strip()
            orig_i = i  # save position before _process_question advances i
            i, item_text = _process_question(lines, i, inline_text)

            # PDF lookback: if item text starts with continuation (lowercase, "or"),
            # the real start may be on the line BEFORE the question number
            if item_text and (item_text[0].islower() or item_text.startswith("or ")):
                prev_idx = orig_i - 1
                while prev_idx >= 0:
                    prev = lines[prev_idx].strip()
                    if not prev or re.match(r'^[\d\s]+$', prev):
                        prev_idx -= 1
                        continue
                    # Strip trailing response codes
                    prev_clean = re.sub(r'\s+\d+(\s+\d+)+\s*$', '', prev)
                    prev_clean = re.sub(r'\s+\d\s*$', '', prev_clean)
                    prev_clean = clean_text(prev_clean)
                    if prev_clean and not is_skip_line(prev_clean) and len(prev_clean) > 3:
                        item_text = prev_clean + " " + item_text
                    break

            _store_question(questions, q_num, item_text, current_section,
                            current_stem, current_battery_range)
            continue

        # ── PDF-style battery item: "24 Your relatives 1 2 3 4 5 6 97 98 99" ──
        # Number + text + trailing response codes, all on one line
        m_pdf_battery = re.match(r'^(\d+)\s+([A-Za-z].*?)(?:\s+\d(?:\s+\d+)*\s*)?$', line)
        if m_pdf_battery and current_battery_range:
            pdf_num = int(m_pdf_battery.group(1))
            if current_battery_range[0] <= pdf_num <= current_battery_range[1]:
                pdf_text = m_pdf_battery.group(2).strip()
                # Strip trailing response codes
                pdf_text = re.sub(r'\s+\d+(\s+\d+)+\s*$', '', pdf_text)
                pdf_text = re.sub(r'\s+\d\s*$', '', pdf_text)
                pdf_text = clean_text(pdf_text)
                # Check for continuation on next line(s)
                j = i + 1
                while j < len(lines) and j < i + 3:
                    next_l = lines[j].strip()
                    # Continuation lines for multi-line items (e.g. "interact with")
                    if next_l and not re.match(r'^\d+\s', next_l) and not _is_question_start(next_l) \
                       and not is_section_header(next_l) and not re.match(r'^[\d\s]+$', next_l) \
                       and not is_skip_line(next_l):
                        # Check if it's a continuation (short text, no numbers at end)
                        if len(next_l) < 60 and not re.search(r'\d\s*$', next_l):
                            pdf_text += " " + next_l
                            j += 1
                            continue
                    break
                _store_question(questions, pdf_num, pdf_text, current_section,
                                current_stem, current_battery_range)
                i = j
                continue

        # ── Bare question number (no period): "133" alone on a line ──
        if re.match(r'^\d+$', line):
            num = int(line)
            # Only treat as question if within a battery range or if next line has text
            if current_battery_range and current_battery_range[0] <= num <= current_battery_range[1]:
                item_text = _gather_item_text(lines, i + 1)
                item_text = clean_text(item_text)
                _store_question(questions, num, item_text, current_section,
                                current_stem, current_battery_range)
                i += 1
                while i < len(lines) and not _is_question_start(lines[i]) and not is_section_header(lines[i]):
                    if re.match(r'^\d+$', lines[i]) and current_battery_range:
                        try:
                            n = int(lines[i])
                            if current_battery_range[0] <= n <= current_battery_range[1]:
                                break
                        except ValueError:
                            pass
                    i += 1
                continue

        i += 1

    return questions


def _is_bare_battery_number(line: str, battery_range: tuple) -> bool:
    """Check if a line is a bare number within the current battery range."""
    if not battery_range:
        return False
    if re.match(r'^\d+$', line):
        try:
            n = int(line)
            return battery_range[0] <= n <= battery_range[1]
        except ValueError:
            pass
    return False


def _is_pdf_battery_item(line: str, battery_range: tuple) -> bool:
    """Check if a line is a PDF-style battery item: 'NUMBER Text...' within range."""
    if not battery_range:
        return False
    m = re.match(r'^(\d+)\s+[A-Za-z]', line)
    if m:
        try:
            n = int(m.group(1))
            return battery_range[0] <= n <= battery_range[1]
        except ValueError:
            pass
    return False


def _is_question_start(line: str) -> bool:
    """Check if a line starts a new question."""
    # "7. text" or "7." (with or without trailing space/text)
    if re.match(r'^\d+\.\s*', line) and not re.match(r'^\d+\.\d', line):
        return True
    if re.match(r'^\d+/\d+\.', line):
        return True
    if re.match(r'^\d+\s*[-–]\s*\d+', line):
        return True
    return False


def _gather_stem(lines: list[str], start: int, battery_range: tuple = None) -> str:
    """Gather stem text starting from a position after a battery range."""
    stem_parts = []
    j = start
    while j < len(lines) and len(stem_parts) < 5:
        next_line = lines[j].strip()
        if _is_question_start(next_line):
            break
        if _is_bare_battery_number(next_line, battery_range):
            break
        if _is_pdf_battery_item(next_line, battery_range):
            break
        if is_skip_line(next_line):
            j += 1
            continue
        if is_section_header(next_line):
            break
        # Check if it's a bare number that could be a battery item
        if re.match(r'^\d+$', next_line):
            try:
                n = int(next_line)
                if n < 200:
                    break
            except ValueError:
                pass
        stem_parts.append(next_line)
        j += 1
    return clean_text(" ".join(stem_parts))


def _gather_item_text(lines: list[str], start: int) -> str:
    """Gather item text starting from a position after a question number."""
    parts = []
    j = start
    while j < len(lines) and len(parts) < 5:
        next_line = lines[j].strip()
        if not next_line:
            j += 1
            continue
        if _is_question_start(next_line):
            break
        if is_section_header(next_line):
            break
        if is_skip_line(next_line):
            j += 1
            continue
        # Check for bare number that could be next battery item
        if re.match(r'^\d+$', next_line):
            try:
                n = int(next_line)
                if n > 6:  # probably a question number, not a response code
                    break
            except ValueError:
                pass
            j += 1
            continue
        parts.append(next_line)
        j += 1
    return " ".join(parts)


def _process_question(lines: list[str], i: int, inline_text: str) -> tuple:
    """Process a question starting at line i. Returns (next_i, item_text)."""
    parts = [inline_text] if inline_text else []
    j = i + 1
    while j < len(lines) and len(parts) < 6:
        next_line = lines[j].strip()
        if not next_line:
            j += 1
            continue
        if _is_question_start(next_line):
            break
        if re.match(r'^\d+\s*[-–]\s*\d+', next_line):
            break
        if is_section_header(next_line):
            break
        if is_skip_line(next_line):
            j += 1
            continue
        # Check for bare number
        if re.match(r'^\d+$', next_line):
            j += 1
            continue
        parts.append(next_line)
        j += 1
    item_text = clean_text(" ".join(parts))
    # Remove leaked response codes at end
    item_text = re.sub(r'\s+\d+(\s+\d+)+\s*$', '', item_text)
    item_text = re.sub(r'\s+\d+\s*$', '', item_text)
    # Remove leaked dotted response options from PDF table extraction
    # e.g., "...the way Very satisfied ............ 1" -> "...the way"
    item_text = re.sub(
        r'\s+(Very good|Good|Bad|Very bad|So so|'
        r'Much better|A little better|About the same|A little worse|Much worse|'
        r'Very satisfied|Fairly satisfied|Not very satisfied|Not at all|'
        r'Strongly agree|Somewhat agree|Somewhat disagree|Strongly disagree|'
        r'A great deal|Quite a lot|Not very much|None at all|'
        r'Yes|No|Always|Often|Sometimes|Rarely|Never|Seldom|'
        r'A lot|Somewhat|A little|Hardly anyone)(\s|\.)+.*$',
        '', item_text, flags=re.IGNORECASE
    )
    return j, item_text


def _store_question(questions: dict, q_num: int, item_text: str,
                     current_section: str, current_stem: str,
                     current_battery_range: tuple) -> None:
    """Store a parsed question in the questions dict. First occurrence wins
    unless new item has more substantive text."""
    notes = ""
    if RE_OPTIONAL_TAG.search(item_text):
        notes = "Optional item"
        item_text = RE_OPTIONAL_TAG.sub('', item_text).strip()

    in_battery = (current_battery_range and
                  current_battery_range[0] <= q_num <= current_battery_range[1])

    key = f"q{q_num}"
    new_text = clean_text(item_text)

    # First occurrence wins — don't overwrite existing entries
    if key in questions and questions[key].get("item_text", ""):
        return

    questions[key] = {
        "section": current_section,
        "stem_text": current_stem if in_battery else "",
        "item_text": new_text,
        "notes": notes,
    }


# ── Step 4: Merge YAML lookup with questionnaire data ────────────────────────

def merge_data(yaml_entries: list[dict], questionnaire_data: dict) -> tuple:
    """Merge YAML lookup table with extracted questionnaire data."""
    rows = []
    unmatched = []

    for entry in yaml_entries:
        wave = entry["wave"]
        qid = entry["question_id"]
        cat = classify_qid(qid) if qid else "not_in_wave"

        row = {
            "wave": wave,
            "question_id": qid,
            "harmonized_name": entry["harmonized_name"],
            "section": "",
            "stem_text": "",
            "item_text": "",
            "response_scale": entry["scale_labels_yaml"],
            "notes": "",
        }

        if not qid:
            row["notes"] = "Not included in this wave"
            rows.append(row)
            continue

        if cat == "metadata":
            row["notes"] = "Metadata variable (not a survey question)"
            row["item_text"] = entry["description"]
            rows.append(row)
            continue

        if cat == "demographics":
            row["notes"] = "Socio-demographic section (not in core questionnaire)"
            row["item_text"] = entry["description"]
            rows.append(row)
            continue

        # Normalize the question ID
        norm_qid = normalize_qid(qid)
        wave_questions = questionnaire_data.get(wave, {})

        # Try to find the question
        q_data = wave_questions.get(norm_qid)

        # Try alternative forms if not found
        if not q_data:
            m = re.match(r'^q(\d+)(.*)$', norm_qid)
            if m:
                num = int(m.group(1))
                suffix = m.group(2)
                if not suffix:
                    # Try zero-padded
                    q_data = wave_questions.get(f"q{num:03d}")

        if q_data:
            row["section"] = q_data.get("section", "")
            row["stem_text"] = q_data.get("stem_text", "")
            row["item_text"] = q_data.get("item_text", "")
            if q_data.get("notes"):
                row["notes"] = q_data["notes"]
        else:
            if cat == "sub_item":
                row["notes"] = "Sub-item/derived variable (not a standalone question)"
                row["item_text"] = entry["description"]
            else:
                row["notes"] = "NOT FOUND in questionnaire document"
                unmatched.append((wave, qid, entry["harmonized_name"]))

        rows.append(row)

    return rows, unmatched


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    print("=" * 70)
    print("Building ABS Verbatim Questionnaire Text Crosswalk")
    print("=" * 70)

    # Step 1: Parse YAML configs
    print("\n[1] Parsing YAML configs...")
    yaml_entries = parse_yaml_lookup()
    n_with_qid = sum(1 for e in yaml_entries if e["question_id"])
    n_missing = sum(1 for e in yaml_entries if not e["question_id"])
    print(f"    {len(yaml_entries)} total entries ({n_with_qid} with question IDs, {n_missing} missing)")

    # Step 2: Extract and parse questionnaire documents
    print("\n[2] Extracting questionnaire documents...")
    questionnaire_data = {}
    for wave in WAVES:
        fmt, path = QUESTIONNAIRE_FILES[wave]
        print(f"    {wave}: {path.name} ({fmt})")
        lines = extract_lines(wave)
        print(f"         {len(lines)} lines extracted")
        questions = parse_questionnaire(wave, lines)
        questionnaire_data[wave] = questions
        print(f"         {len(questions)} questions parsed")

    # Step 3: Merge
    print("\n[3] Merging YAML lookup with questionnaire data...")
    rows, unmatched = merge_data(yaml_entries, questionnaire_data)

    n_verbatim = sum(1 for r in rows if r["item_text"] and "NOT FOUND" not in r.get("notes", ""))
    n_not_found = sum(1 for r in rows if "NOT FOUND" in r.get("notes", ""))
    n_not_in_wave = sum(1 for r in rows if not r["question_id"])
    n_metadata = sum(1 for r in rows if "Metadata" in r.get("notes", ""))
    n_demographics = sum(1 for r in rows if "Socio-demographic" in r.get("notes", ""))
    n_sub_item = sum(1 for r in rows if "Sub-item" in r.get("notes", ""))
    print(f"    {n_verbatim} items with verbatim/description text")
    print(f"    {n_not_found} items NOT FOUND in questionnaire")
    print(f"    {n_not_in_wave} items not included in wave")
    print(f"    {n_metadata} metadata, {n_demographics} demographics, {n_sub_item} sub-items")

    if unmatched:
        print(f"\n    Truly unmatched items ({len(unmatched)}):")
        for wave, qid, name in sorted(unmatched)[:20]:
            print(f"      {wave} {qid:12s} {name}")
        if len(unmatched) > 20:
            print(f"      ... and {len(unmatched) - 20} more")

    # Step 4: Sort and write CSV
    print(f"\n[4] Writing CSV to {OUTPUT_PATH}...")
    rows.sort(key=lambda r: (r["harmonized_name"], r["wave"]))

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    fieldnames = [
        "wave", "question_id", "harmonized_name", "section",
        "stem_text", "item_text", "response_scale", "notes",
    ]

    with open(OUTPUT_PATH, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"    Wrote {len(rows)} rows")

    # Quality summary per wave
    print("\n[5] Quality summary:")
    for wave in WAVES:
        wave_rows = [r for r in rows if r["wave"] == wave]
        with_text = sum(1 for r in wave_rows if r["item_text"])
        with_qid = sum(1 for r in wave_rows if r["question_id"])
        not_found = sum(1 for r in wave_rows if "NOT FOUND" in r.get("notes", ""))
        print(f"    {wave}: {with_text}/{with_qid} with text ({not_found} not found)")

    print("\nDone.")


if __name__ == "__main__":
    main()
