from __future__ import annotations

import logging
import threading

import pystray

from .bridge import BridgeApp
from .icons import get_tray_icon

logger = logging.getLogger(__name__)


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
            get_tray_icon(False),
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
        self._icon.icon = get_tray_icon(state.obs_connected)
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
