"""Pinned wago.tools downloads: cached on disk, validated before they are cached, never executed."""

import urllib.request
from collections.abc import Callable
from pathlib import Path

from .csvtable import Row, parse_csv
from .fsio import atomic_write

DB2_URL = "https://wago.tools/db2/{name}/csv?build={build}"


def read_source(
    url: str, path: Path, *, user_agent: str, refresh: bool = False, offline: bool = False, timeout: int = 60
) -> tuple[bytes, bool]:
    """The cached bytes at `path`, or a download of `url`; whether it was downloaded. `offline` forbids the network."""
    if path.exists() and not refresh:
        return path.read_bytes(), False
    if offline:
        raise ValueError(f"Missing cached source: {path}")
    request = urllib.request.Request(url, headers={"User-Agent": user_agent})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        data = response.read()
    if not data.strip() or data.lstrip().startswith(b"<"):
        raise ValueError(f"Expected data, received empty data or HTML from {url}")
    return data, True


def fetch(
    url: str,
    path: Path,
    *,
    user_agent: str,
    refresh: bool = False,
    offline: bool = False,
    timeout: int = 60,
    validate: Callable[[bytes], object] | None = None,
) -> bytes:
    """`read_source`, then `validate` (raising rejects the data); a download is cached only after it passes."""
    data, fetched = read_source(url, path, user_agent=user_agent, refresh=refresh, offline=offline, timeout=timeout)
    if validate:
        validate(data)
    if fetched:
        atomic_write(path, data)
    return data


def db2_rows(
    name: str,
    build: str,
    cache: Path,
    *,
    user_agent: str,
    refresh: bool = False,
    offline: bool = False,
    timeout: int = 60,
    **options,
) -> list[Row]:
    """One DB2 table at one build as validated rows (`parse_csv` options pass through), cached in `cache`."""
    path = cache / f"{name}-{build}.csv"
    data, fetched = read_source(
        DB2_URL.format(name=name, build=build),
        path,
        user_agent=user_agent,
        refresh=refresh,
        offline=offline,
        timeout=timeout,
    )
    rows = parse_csv(data.decode("utf-8-sig"), name, **options)
    if fetched:
        atomic_write(path, data)
    return rows
