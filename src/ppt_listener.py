from __future__ import annotations

import logging
import threading
import time
from typing import Callable

import pythoncom
import win32com.client

logger = logging.getLogger(__name__)

SlideChangeCallback = Callable[[int, str], None]
IDLE_POLL_INTERVAL = 0.5


class PPTListener:
    """Polls PowerPoint for slideshow slide changes."""

    def __init__(
        self,
        on_slide_change: SlideChangeCallback,
        poll_interval: float = 0.05,
    ) -> None:
        self.on_slide_change = on_slide_change
        self.poll_interval = poll_interval
        self._running = False
        self._thread: threading.Thread | None = None
        self._last_slide: int | None = None
        self._slideshow_active = False
        self._slide_notes_cache: dict[int, str] = {}

    def start(self) -> None:
        if self._running:
            return
        self._running = True
        self._thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._thread.start()
        logger.info("PowerPoint listener started")

    def stop(self) -> None:
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None
        self._last_slide = None
        self._slideshow_active = False
        self._slide_notes_cache = {}
        logger.info("PowerPoint listener stopped")

    @property
    def slideshow_active(self) -> bool:
        return self._slideshow_active

    def _poll_loop(self) -> None:
        pythoncom.CoInitialize()
        try:
            while self._running:
                self._check_slide()
                interval = self.poll_interval if self._slideshow_active else IDLE_POLL_INTERVAL
                time.sleep(interval)
        finally:
            pythoncom.CoUninitialize()

    def _check_slide(self) -> None:
        try:
            app = win32com.client.GetActiveObject("PowerPoint.Application")
        except Exception:
            self._handle_no_slideshow()
            return

        if app.SlideShowWindows.Count == 0:
            self._handle_no_slideshow()
            return

        if not self._slideshow_active:
            self._build_slide_cache(app)

        self._slideshow_active = True
        view = app.SlideShowWindows(1).View
        current_slide = int(view.CurrentShowPosition)

        if current_slide == self._last_slide:
            return

        self._last_slide = current_slide
        notes = self._slide_notes_cache.get(current_slide, "")
        logger.info("Slide %s changed", current_slide)
        self.on_slide_change(current_slide, notes)

    def _build_slide_cache(self, app) -> None:
        try:
            presentation = app.ActivePresentation
            cache: dict[int, str] = {}
            for index in range(1, presentation.Slides.Count + 1):
                cache[index] = _read_slide_notes(presentation.Slides(index))
            self._slide_notes_cache = cache
            logger.info("Cached speaker notes for %s slides", len(cache))
        except Exception as exc:
            logger.warning("Could not cache slide notes: %s", exc)
            self._slide_notes_cache = {}

    def _handle_no_slideshow(self) -> None:
        if self._slideshow_active or self._last_slide is not None:
            logger.info("PowerPoint slideshow ended")
        self._slideshow_active = False
        self._last_slide = None
        self._slide_notes_cache = {}


def _read_slide_notes(slide) -> str:
    try:
        notes_page = slide.NotesPage
        parts: list[str] = []
        for index in range(1, notes_page.Shapes.Count + 1):
            shape = notes_page.Shapes(index)
            if shape.HasTextFrame and shape.TextFrame.HasText:
                parts.append(shape.TextFrame.TextRange.Text)
        return "\n".join(parts)
    except Exception as exc:
        logger.warning("Could not read speaker notes: %s", exc)
        return ""
