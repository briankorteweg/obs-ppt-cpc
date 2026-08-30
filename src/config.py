from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

ROOT_DIR = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_PATH = ROOT_DIR / "config.yaml"
EXAMPLE_CONFIG_PATH = ROOT_DIR / "config.example.yaml"


@dataclass
class OBSConfig:
    host: str
    port: int
    password: str


@dataclass
class AppConfig:
    obs: OBSConfig
    poll_interval: float


def load_config(path: Path | None = None) -> AppConfig:
    config_path = path or DEFAULT_CONFIG_PATH

    if not config_path.exists():
        raise FileNotFoundError(
            f"Config not found at {config_path}. "
            f"Copy config.example.yaml to config.yaml and fill in your OBS WebSocket password."
        )

    with config_path.open(encoding="utf-8") as handle:
        raw = yaml.safe_load(handle) or {}

    obs_raw = raw.get("obs", {})
    return AppConfig(
        obs=OBSConfig(
            host=str(obs_raw.get("host", "localhost")),
            port=int(obs_raw.get("port", 4455)),
            password=str(obs_raw.get("password", "")),
        ),
        poll_interval=float(raw.get("poll_interval", 0.05)),
    )
