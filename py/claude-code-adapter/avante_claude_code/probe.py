"""
Cheap, model-free queries against the Claude Code CLI.

Everything here shells out to a CLI subcommand that answers locally: no turn is
started, no tokens are spent. Used by Avante's health check and by
`:AvanteClaudeCodeStatus`.
"""

from __future__ import annotations

import json
import subprocess
from typing import Any

#: Seconds to wait for a local CLI subcommand before giving up.
PROBE_TIMEOUT = 30.0


def _run(argv: list[str], env: dict[str, str] | None = None) -> tuple[int, str, str]:
    try:
        completed = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=PROBE_TIMEOUT,
            check=False,
            env=env,
        )
    except FileNotFoundError:
        return 127, "", f"{argv[0]} not found"
    except subprocess.TimeoutExpired:
        return 124, "", f"{' '.join(argv)} timed out after {PROBE_TIMEOUT:.0f}s"
    except OSError as exc:
        return 1, "", str(exc)
    return completed.returncode, completed.stdout, completed.stderr


def _run_json(argv: list[str], env: dict[str, str] | None = None) -> dict[str, Any]:
    """Run a CLI subcommand that prints JSON and normalise the outcome."""
    code, stdout, stderr = _run(argv, env)
    if code != 0:
        return {"ok": False, "error": (stderr or stdout).strip() or f"exited with status {code}"}
    try:
        return {"ok": True, "value": json.loads(stdout)}
    except json.JSONDecodeError:
        return {"ok": False, "error": f"unparseable output: {stdout.strip()[:200]}"}


def auth_status(cli_path: str = "claude", env: dict[str, str] | None = None) -> dict[str, Any]:
    """Report whether Claude Code is signed in, and how."""
    return _run_json([cli_path, "auth", "status", "--json"], env)


def plugins(cli_path: str = "claude", env: dict[str, str] | None = None) -> dict[str, Any]:
    """List the plugins Claude Code has installed."""
    return _run_json([cli_path, "plugin", "list", "--json"], env)


def version(cli_path: str = "claude", env: dict[str, str] | None = None) -> dict[str, Any]:
    """Report the CLI's version string."""
    code, stdout, stderr = _run([cli_path, "--version"], env)
    if code != 0:
        return {"ok": False, "error": (stderr or stdout).strip() or f"exited with status {code}"}
    return {"ok": True, "value": stdout.strip()}


def probe(cli_path: str = "claude", env: dict[str, str] | None = None) -> dict[str, Any]:
    """Collect everything Avante wants to know about the local installation."""
    return {
        "cli_path": cli_path,
        "version": version(cli_path, env),
        "auth": auth_status(cli_path, env),
        "plugins": plugins(cli_path, env),
    }
