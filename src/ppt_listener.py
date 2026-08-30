from __future__ import annotations

import logging
import threading
from typing import Callable

import pythoncom
import win32com.client

logger = logging.getLogger(__name__)

SlideChangeCallback = Callable[[int, str], None]
IDLE_POLL_INTERVAL = 0.5
# PowerPoint ppPlaceholderBody — the speaker-notes text on a notes page.
PP_PLACEHOLDER_BODY = 2


class PPTListener:
    """Polls PowerPoint for slideshow slide changes."""

    def __init__(
        self,
        on_slide_change: SlideChangeCallback,
        poll_interval: float = 0.05,
    ) -> None:
        self.on_slide_change = on_slide_change
        self.poll_interval = poll_interval
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._last_slide: int | None = None
        self._slideshow_active = False
        self._slide_notes_cache: dict[int, str] = {}
        self._app = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return

        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._poll_loop,
            name="PowerPointListener",
            daemon=True,
        )
        self._thread.start()
        logger.info("PowerPoint listener started")

    def stop(self) -> None:
        self._stop_event.set()

        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None

        self._app = None
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
            while not self._stop_event.is_set():
                try:
                    self._check_slide()
                except Exception:
                    logger.exception("Unexpected PowerPoint polling error")
                    self._disconnect_powerpoint()

                interval = (
                    self.poll_interval
                    if self._slideshow_active
                    else IDLE_POLL_INTERVAL
                )
                self._stop_event.wait(interval)
        finally:
            self._disconnect_powerpoint()
            pythoncom.CoUninitialize()

    def _connect_powerpoint(self) -> bool:
        if self._app is not None:
            return True

        try:
            self._app = win32com.client.GetActiveObject("PowerPoint.Application")
            logger.debug("Connected to the active PowerPoint application")
            return True
        except pythoncom.com_error:
            self._app = None
            return False
        except Exception as exc:
            logger.debug("Could not connect to PowerPoint: %s", exc)
            self._app = None
            return False

    def _disconnect_powerpoint(self) -> None:
        self._app = None
        self._handle_no_slideshow()

    def _check_slide(self) -> None:
        if not self._connect_powerpoint():
            self._handle_no_slideshow()
            return

        app = self._app

        try:
            slideshow_windows = app.SlideShowWindows
            slideshow_count = slideshow_windows.Count
        except (AttributeError, pythoncom.com_error) as exc:
            logger.debug(
                "Could not access PowerPoint SlideShowWindows; reconnecting: %s",
                exc,
            )
            self._disconnect_powerpoint()
            return

        if slideshow_count == 0:
            self._handle_no_slideshow()
            return

        try:
            slideshow_window = slideshow_windows.Item(1)
            view = slideshow_window.View
            current_slide = _current_slide_index(view)
        except (AttributeError, pythoncom.com_error, TypeError, ValueError) as exc:
            logger.debug("Could not read the current PowerPoint slide: %s", exc)
            self._disconnect_powerpoint()
            return

        if current_slide < 1:
            return

        if not self._slideshow_active:
            self._build_slide_cache(app)

        self._slideshow_active = True

        if current_slide == self._last_slide:
            return

        self._last_slide = current_slide
        notes = self._notes_for_slide(view, current_slide)

        logger.info("Slide %s changed", current_slide)

        try:
            self.on_slide_change(current_slide, notes)
        except Exception:
            logger.exception("Slide-change callback failed")

    def _notes_for_slide(self, view, current_slide: int) -> str:
        if current_slide in self._slide_notes_cache:
            return self._slide_notes_cache[current_slide]

        notes = _read_view_slide_notes(view)
        if notes is not None:
            self._slide_notes_cache[current_slide] = notes
            return notes

        try:
            notes = _read_slide_notes(self._app.ActivePresentation.Slides.Item(current_slide))
        except (AttributeError, pythoncom.com_error) as exc:
            logger.debug("Could not read notes for slide %s: %s", current_slide, exc)
            notes = ""

        self._slide_notes_cache[current_slide] = notes
        return notes

    def _build_slide_cache(self, app) -> None:
        try:
            presentation = app.ActivePresentation
            cache: dict[int, str] = {}

            for index in range(1, presentation.Slides.Count + 1):
                cache[index] = _read_slide_notes(presentation.Slides.Item(index))

            self._slide_notes_cache = cache
            logger.info("Cached speaker notes for %s slides", len(cache))

        except (AttributeError, pythoncom.com_error) as exc:
            logger.warning("Could not cache slide notes: %s", exc)
            self._slide_notes_cache = {}

    def _handle_no_slideshow(self) -> None:
        if self._slideshow_active or self._last_slide is not None:
            logger.info("PowerPoint slideshow ended")

        self._slideshow_active = False
        self._last_slide = None
        self._slide_notes_cache = {}


def _current_slide_index(view) -> int:
    try:
        return int(view.Slide.SlideIndex)
    except (AttributeError, pythoncom.com_error, TypeError, ValueError):
        return int(view.CurrentShowPosition)


def _read_view_slide_notes(view) -> str | None:
    try:
        return _read_slide_notes(view.Slide)
    except (AttributeError, pythoncom.com_error):
        return None


def _read_slide_notes(slide) -> str:
    try:
        notes_page = slide.NotesPage
        body = _notes_body_text(notes_page)
        if body is not None:
            return body
        return _all_notes_text(notes_page)
    except (AttributeError, pythoncom.com_error) as exc:
        logger.warning("Could not read speaker notes: %s", exc)
        return ""


def _notes_body_text(notes_page) -> str | None:
    shapes = notes_page.Shapes
    for index in range(1, shapes.Count + 1):
        shape = shapes.Item(index)
        try:
            if int(shape.PlaceholderFormat.Type) != PP_PLACEHOLDER_BODY:
                continue
        except (AttributeError, pythoncom.com_error, TypeError, ValueError):
            continue
        return _shape_text(shape)
    return None


def _all_notes_text(notes_page) -> str:
    parts: list[str] = []
    shapes = notes_page.Shapes
    for index in range(1, shapes.Count + 1):
        text = _shape_text(shapes.Item(index))
        if text:
            parts.append(text)
    return "\n".join(parts)


def _shape_text(shape) -> str:
    try:
        if shape.HasTextFrame and shape.TextFrame.HasText:
            return _normalize_notes_text(shape.TextFrame.TextRange.Text)
    except (AttributeError, pythoncom.com_error):
        return ""
    return ""


def _normalize_notes_text(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n").strip()
