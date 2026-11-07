"""Fail-closed parsing of wago.tools DB2 CSV exports.

A malformed export must stop a generator, never feed it shifted columns: a duplicate header makes DictReader keep
the last column silently, and a short or long row fills fields with None or a stray key.
"""

import csv
import io
import math
import re
from collections import Counter
from collections.abc import Iterable, Iterator

INTEGER = re.compile(r"[+-]?\d+")

Row = dict[str, str | int | float]


def numbered(reader: csv.DictReader, name: str) -> Iterator[tuple[int, dict]]:
    """Each row with its line number; a csv.Error (the reader's strict mode) becomes a ValueError."""
    rows = iter(reader)
    while True:
        try:
            row = next(rows)
        except StopIteration:
            return
        except csv.Error as error:
            raise ValueError(f"{name}:{reader.line_num}: invalid CSV: {error}") from error
        yield reader.line_num, row


def parse_csv(
    text: str,
    name: str,
    *,
    required: Iterable[str] = (),
    unique: str | None = "ID",
    ints: Iterable[str] = (),
    floats: Iterable[str] = (),
    allow_empty: bool = False,
) -> list[Row]:
    """The rows of one export as dicts of strings, validated.

    - the header has no duplicate columns and every `required` (and every `ints`/`floats`) column
    - every row has exactly one value per header column
    - `unique` names an ID column: when the export has it, an ID appears once; `ID` is an exact integer
      and its uniqueness is numeric, while the returned value stays a string unless requested in `ints`
    - `ints` columns are exact integers (no whitespace, underscores or fractions) and `floats` columns are finite
      numbers; both come back converted, every other value stays the export's string
    - an export with no rows fails unless `allow_empty`
    """
    ints, floats = tuple(ints), tuple(floats)
    reader = csv.DictReader(io.StringIO(text), strict=True)
    try:
        fields = reader.fieldnames or []
    except csv.Error as error:
        raise ValueError(f"{name}: invalid CSV header: {error}") from error
    repeated = sorted(column for column, count in Counter(fields).items() if count > 1)
    if repeated:
        raise ValueError(f"{name}: duplicate columns {repeated}")
    missing = sorted({*required, *ints, *floats} - set(fields))
    if missing:
        raise ValueError(f"{name}: missing required columns {missing} (or not a CSV export)")
    rows: list[Row] = []
    seen: set[str | int] = set()
    for line, row in numbered(reader, name):
        where = f"{name}:{line}"
        if None in row or None in row.values():
            raise ValueError(f"{where}: malformed CSV row (expected {len(fields)} values)")
        parsed: Row = dict(row)
        for column in ints:
            if not INTEGER.fullmatch(row[column]):
                raise ValueError(f"{where}: invalid integer {column}={row[column]!r}")
            parsed[column] = int(row[column])
        for column in floats:
            try:
                value = float(row[column])
            except ValueError:
                value = math.nan
            if not math.isfinite(value):
                raise ValueError(f"{where}: invalid number {column}={row[column]!r}")
            parsed[column] = value
        if unique and unique in fields:
            identifier: str | int = row[unique]
            if unique == "ID":
                if not INTEGER.fullmatch(row[unique]):
                    raise ValueError(f"{where}: invalid integer ID={row[unique]!r}")
                identifier = int(row[unique])
            if identifier in seen:
                raise ValueError(f"{where}: duplicate {unique} {identifier}")
            seen.add(identifier)
        rows.append(parsed)
    if not rows and not allow_empty:
        raise ValueError(f"{name}: empty export")
    return rows
