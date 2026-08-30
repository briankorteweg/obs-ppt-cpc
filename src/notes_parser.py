from __future__ import annotations

import re

OBS_SCENE_RE = re.compile(r"^OBS:\s*(.+)$", re.IGNORECASE)


def parse_scene(notes_text: str) -> str | None:
    """Return the OBS scene name from speaker notes, if present."""
    for line in notes_text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if match := OBS_SCENE_RE.match(stripped):
            return match.group(1).strip()
    return None
