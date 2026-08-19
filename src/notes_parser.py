from __future__ import annotations

import re

OBS_SCENE_RE = re.compile(r"^OBS:\s*(.+)$", re.IGNORECASE)
OBS_DEFAULT_RE = re.compile(r"^OBSDEF:\s*(.+)$", re.IGNORECASE)


def parse_notes(notes_text: str) -> tuple[str | None, str | None]:
    """Return (scene_name, default_scene) parsed from speaker notes."""
    scene_name: str | None = None
    default_scene: str | None = None

    for line in notes_text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if match := OBS_SCENE_RE.match(stripped):
            scene_name = match.group(1).strip()
        elif match := OBS_DEFAULT_RE.match(stripped):
            default_scene = match.group(1).strip()

    return scene_name, default_scene
