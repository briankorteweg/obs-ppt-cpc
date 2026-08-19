from __future__ import annotations

import logging

import obsws_python as obs

logger = logging.getLogger(__name__)


class OBSClient:
    def __init__(self, host: str, port: int, password: str) -> None:
        self.host = host
        self.port = port
        self.password = password
        self._client: obs.ReqClient | None = None

    def connect(self) -> None:
        self.disconnect()
        self._client = obs.ReqClient(
            host=self.host,
            port=self.port,
            password=self.password,
            timeout=3,
        )
        version = self._client.get_version()
        logger.info(
            "Connected to OBS %s (WebSocket %s)",
            version.obs_version,
            version.obs_web_socket_version,
        )

    def disconnect(self) -> None:
        self._client = None

    def is_connected(self) -> bool:
        if self._client is None:
            return False
        try:
            self._client.get_version()
            return True
        except Exception:
            self._client = None
            return False

    def switch_scene(self, scene_name: str) -> None:
        if self._client is None:
            self.connect()
        assert self._client is not None
        try:
            self._client.set_current_program_scene(scene_name)
        except Exception:
            self.connect()
            assert self._client is not None
            self._client.set_current_program_scene(scene_name)
        logger.info("Switched OBS scene to %r", scene_name)

    def list_scenes(self) -> list[str]:
        if not self.is_connected():
            self.connect()
        assert self._client is not None
        response = self._client.get_scene_list()
        return [scene["sceneName"] for scene in response.scenes]
