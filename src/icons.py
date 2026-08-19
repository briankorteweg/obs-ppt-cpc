from __future__ import annotations

from functools import lru_cache
from io import BytesIO
from pathlib import Path

import skia
from PIL import Image

# Phosphor Icons (MIT) - https://github.com/phosphor-icons/core
ASSETS_DIR = Path(__file__).resolve().parent.parent / "assets" / "icons"
PLAY_CIRCLE_FILL_SVG = (ASSETS_DIR / "play-circle-fill.svg").read_text(encoding="utf-8")
WARNING_FILL_SVG = (ASSETS_DIR / "warning-fill.svg").read_text(encoding="utf-8")

CONNECTED_COLOR = "#22c55e"
WARNING_COLOR = "#eab308"
TRAY_ICON_SIZE = 64


def _render_svg_icon(svg_template: str, color: str, size: int) -> Image.Image:
    svg = svg_template.replace("currentColor", color)
    stream = skia.MemoryStream(svg.encode("utf-8"))
    svg_dom = skia.SVGDOM.MakeFromStream(stream)
    if svg_dom is None:
        raise RuntimeError("Failed to load tray icon SVG")

    surface = skia.Surface(size, size)
    canvas = surface.getCanvas()
    canvas.clear(skia.Color4f(0, 0, 0, 0))
    svg_dom.setContainerSize(skia.Size(size, size))
    svg_dom.render(canvas)

    png_data = surface.makeImageSnapshot().encodeToData()
    return Image.open(BytesIO(bytes(png_data.data()))).convert("RGBA")


@lru_cache(maxsize=4)
def get_tray_icon(connected: bool, size: int = TRAY_ICON_SIZE) -> Image.Image:
    if connected:
        return _render_svg_icon(PLAY_CIRCLE_FILL_SVG, CONNECTED_COLOR, size)
    return _render_svg_icon(WARNING_FILL_SVG, WARNING_COLOR, size)
