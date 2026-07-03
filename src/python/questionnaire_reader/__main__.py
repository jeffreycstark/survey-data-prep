"""CLI: python -m questionnaire_reader <parse|crossvalidate> --survey <slug>."""

from __future__ import annotations

import argparse
import sys

from .crossvalidate.tri_source import crossvalidate_survey
from .parsers import SURVEY_PARSERS
from .schema import write_outputs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="questionnaire_reader")
    sub = ap.add_subparsers(dest="command", required=True)

    p_parse = sub.add_parser(
        "parse", help="parse questionnaire originals -> codebook-v1 parquet"
    )
    p_parse.add_argument(
        "--survey", required=True, choices=sorted(SURVEY_PARSERS.keys())
    )

    p_xval = sub.add_parser(
        "crossvalidate", help="tri-source polarity cross-validation -> CSV"
    )
    p_xval.add_argument("--survey", required=True)

    args = ap.parse_args(argv)

    if args.command == "parse":
        rows = SURVEY_PARSERS[args.survey]()
        core, side = write_outputs(args.survey, rows)
        n_vars = len({(r.wave, r.raw_var) for r in rows})
        print(
            f"[parse] {args.survey}: {len(rows)} code rows across "
            f"{n_vars} (wave, variable) cells"
        )
        print(f"[parse] contract parquet: {core}")
        print(f"[parse] raw sidecar:      {side}")
        return 0

    crossvalidate_survey(args.survey)
    return 0


if __name__ == "__main__":
    sys.exit(main())
