from __future__ import annotations

import logging
import threading

import pystray
from PIL import Image, ImageDraw

from .bridge import BridgeApp

logger = logging.getLogger(__name__)


def _create_icon(connected: bool, active: bool) -> Image.Image:
    color = (46, 160, 67) if connected and active else (46, 125, 217) if connected else (180, 60, 60)
    image = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.ellipse((8, 8, 56, 56), fill=color)
    draw.rectangle((24, 20, 40, 44), fill="white")
    draw.rectangle((28, 24, 36, 32), fill=color)
    return image


class TrayApp:
    def __init__(self, bridge: BridgeApp) -> None:
        self.bridge = bridge
        self._icon: pystray.Icon | None = None
        self._status_item: pystray.MenuItem | None = None
        self._scene_item: pystray.MenuItem | None = None

    def run(self) -> None:
        self.bridge.add_state_listener(self._on_state_change)
        self.bridge.start()

        self._status_item = pystray.MenuItem(lambda item: self.bridge.state.status_message, None, enabled=False)
        self._scene_item = pystray.MenuItem(lambda item: self._scene_text(), None, enabled=False)

        menu = pystray.Menu(
            self._status_item,
            self._scene_item,
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Reconnect OBS", self._reconnect_obs),
            pystray.MenuItem("Quit", self._quit),
        )

        self._icon = pystray.Icon(
            "obs-ppt-cpc",
            _create_icon(False, False),
            "OBS PPT CPC",
            menu,
        )

        monitor = threading.Thread(target=self._monitor_slideshow, daemon=True)
        monitor.start()
        self._icon.run()
        self.bridge.stop()

    def _scene_text(self) -> str:
        scene = self.bridge.state.last_scene
        return f"Last scene: {scene}" if scene else "Last scene: (none)"

    def _on_state_change(self, state) -> None:
        if self._icon is None:
            return
        self._icon.icon = _create_icon(state.obs_connected, state.slideshow_active)
        title = state.status_message
        if state.slideshow_active:
            title = f"[Live] {title}"
        self._icon.title = title
        self._icon.update_menu()

    def _monitor_slideshow(self) -> None:
        last_active = False
        while self._icon is not None and self._icon.visible:
            active = self.bridge.ppt_listener.slideshow_active
            if active != last_active:
                last_active = active
                self.bridge.state.slideshow_active = active
                self._on_state_change(self.bridge.state)
            threading.Event().wait(0.5)

    def _reconnect_obs(self, icon, item) -> None:
        self.bridge.reconnect_obs()

    def _quit(self, icon, item) -> None:
        icon.stop()
