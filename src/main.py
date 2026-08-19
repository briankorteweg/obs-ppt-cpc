from __future__ import annotations

import argparse
import logging
import sys

from .bridge import BridgeApp
from .config import load_config
from .tray_app import TrayApp


def _configure_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Switch OBS scenes from PowerPoint speaker notes.")
    parser.add_argument(
        "--switch",
        metavar="SCENE",
        help="Switch to an OBS scene and exit (useful for testing OBS connection).",
    )
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging.")
    args = parser.parse_args(argv)
    _configure_logging(args.verbose)

    try:
        config = load_config()
    except FileNotFoundError as exc:
        print(exc, file=sys.stderr)
        return 1

    bridge = BridgeApp(config)

    if args.switch:
        try:
            bridge.switch_scene_manual(args.switch)
            print(f"Switched to scene: {args.switch}")
            return 0
        except Exception as exc:
            print(f"Failed to switch scene: {exc}", file=sys.stderr)
            return 1

    TrayApp(bridge).run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
