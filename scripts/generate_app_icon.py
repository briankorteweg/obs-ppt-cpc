from __future__ import annotations

import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from src.icons import write_app_icon


def main() -> None:
    path = write_app_icon()
    print(f"Wrote {path}")


if __name__ == "__main__":
    main()
