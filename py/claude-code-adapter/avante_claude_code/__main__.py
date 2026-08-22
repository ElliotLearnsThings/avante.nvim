"""``python -m avante_claude_code`` entry point."""

from __future__ import annotations

import sys

from .adapter import main

if __name__ == "__main__":
    sys.exit(main())
