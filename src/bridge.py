from __future__ import annotations

import logging
import threading
from dataclasses import dataclass, field

from .config import AppConfig
from .notes_parser import parse_notes
from .obs_client import OBSClient
from .ppt_listener import PPTListener

logger = logging.getLogger(__name__)


@dataclass
class AppState:
    obs_connected: bool = False
    slideshow_active: bool = False
    last_scene: str | None = None
    status_message: str = "Starting..."


class BridgeApp:
    def __init__(self, config: AppConfig) -> None:
        self.config = config
        self.state = AppState()
        self._runtime_default_scene = config.default_scene
        self._obs = OBSClient(
            host=config.obs.host,
            port=config.obs.port,
            password=config.obs.password,
        )
        self._ppt = PPTListener(
            on_slide_change=self._on_slide_change,
            poll_interval=config.poll_interval,
        )
        self._lock = threading.Lock()
        self._on_state_change: list = []

    def add_state_listener(self, callback) -> None:
        self._on_state_change.append(callback)

    def _notify_state_change(self) -> None:
        for callback in self._on_state_change:
            try:
                callback(self.state)
            except Exception:
                logger.exception("State listener failed")

    def _set_status(self, message: str, **kwargs) -> None:
        self.state.status_message = message
        for key, value in kwargs.items():
            setattr(self.state, key, value)
        self._notify_state_change()

    def start(self) -> None:
        try:
            self._obs.connect()
            self._set_status("Connected to OBS", obs_connected=True)
        except Exception as exc:
            logger.exception("Failed to connect to OBS")
            self._set_status(f"OBS offline: {exc}", obs_connected=False)

        self._ppt.start()
        self._set_status(
            "Watching for PowerPoint slideshow",
            obs_connected=self.state.obs_connected,
            slideshow_active=False,
        )

    def stop(self) -> None:
        self._ppt.stop()
        self._obs.disconnect()
        self._set_status("Stopped", obs_connected=False, slideshow_active=False)

    def reconnect_obs(self) -> None:
        try:
            self._obs.connect()
            self._set_status("Connected to OBS", obs_connected=True)
        except Exception as exc:
            logger.exception("OBS reconnect failed")
            self._set_status(f"OBS offline: {exc}", obs_connected=False)

    def switch_scene_manual(self, scene_name: str) -> None:
        with self._lock:
            self._switch_scene(scene_name)

    def _on_slide_change(self, slide_number: int, notes: str) -> None:
        scene_name, default_scene = parse_notes(notes)

        if default_scene:
            self._runtime_default_scene = default_scene
            logger.info("Default scene set to %r from slide %s", default_scene, slide_number)

        if not scene_name:
            logger.debug(
                "Slide %s has no OBS tag; keeping scene %r",
                slide_number,
                self.state.last_scene,
            )
            return

        self._switch_scene(scene_name, slide_number=slide_number)

    def _switch_scene(self, scene_name: str, slide_number: int | None = None) -> None:
        try:
            with self._lock:
                self._obs.switch_scene(scene_name)
            self.state.last_scene = scene_name
            if slide_number is not None:
                message = f"Slide {slide_number} -> {scene_name}"
            else:
                message = f"Switched to {scene_name}"
            self._set_status(
                message,
                obs_connected=True,
                slideshow_active=self._ppt.slideshow_active,
                last_scene=scene_name,
            )
        except Exception as exc:
            logger.exception("Scene switch failed")
            self._set_status(
                f"Scene switch failed: {exc}",
                obs_connected=False,
                slideshow_active=self._ppt.slideshow_active,
            )

    @property
    def ppt_listener(self) -> PPTListener:
        return self._ppt
