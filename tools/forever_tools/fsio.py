"""Atomic file writes: a unique temporary file beside the target, then one replace."""

import contextlib
import os
import tempfile
from collections.abc import Mapping
from pathlib import Path

Data = bytes | str


def _encode(data: Data) -> bytes:
    return data.encode("utf-8") if isinstance(data, str) else data


def _stage(path: Path, data: Data) -> Path:
    """Write `data` to a fresh temporary file beside `path`; its name never collides with another writer's."""
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.", suffix=".tmp", delete=False)
    temporary = Path(handle.name)
    try:
        with handle:
            handle.write(_encode(data))
            handle.flush()
            os.fsync(handle.fileno())
        temporary.chmod(0o644)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
    return temporary


def atomic_write(path: Path, data: Data) -> None:
    """Replace `path` with `data` or leave it untouched; readers never see a partial file."""
    temporary = _stage(path, data)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def publish(outputs: Mapping[Path, Data]) -> None:
    """Write several outputs as one batch: every file is staged before the first is replaced, and a failed
    replace puts the files already replaced back, so a generator never leaves a mixed set."""
    staged: dict[Path, Path] = {}
    originals: dict[Path, bytes | None] = {}
    replaced: list[Path] = []
    try:
        for path, data in outputs.items():
            staged[path] = _stage(path, data)
            originals[path] = path.read_bytes() if path.exists() else None
        for path, temporary in staged.items():
            temporary.replace(path)
            replaced.append(path)
    except BaseException:
        for path in replaced:
            original = originals[path]
            if original is None:
                path.unlink(missing_ok=True)
            else:
                atomic_write(path, original)
        raise
    finally:
        for temporary in staged.values():
            with contextlib.suppress(OSError):
                temporary.unlink(missing_ok=True)
