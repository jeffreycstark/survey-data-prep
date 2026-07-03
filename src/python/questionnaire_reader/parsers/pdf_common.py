"""Shared PDF helper: pdftotext -layout extraction."""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


def pdf_to_text(path: Path) -> str | None:
    """Extract layout-preserving text via poppler's pdftotext CLI."""
    if shutil.which("pdftotext") is None or not path.is_file():
        return None
    proc = subprocess.run(
        ["pdftotext", "-layout", str(path), "-"],
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.stdout if proc.returncode == 0 else None
