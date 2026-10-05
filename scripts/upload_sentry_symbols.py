#!/usr/bin/env python3
"""Explicit developer/CI upload of build-matched dSYMs; never run from the app."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


def main():
    root = Path(__file__).resolve().parent.parent
    paths = [Path(p).resolve() for p in sys.argv[1:]] or [root / "build/PinShot.app.dSYM"]
    if any(not p.is_dir() or p.suffix != ".dSYM" for p in paths):
        raise RuntimeError("Build the app first and supply existing .dSYM directories.")
    cli = shutil.which("sentry-cli")
    if not cli:
        raise RuntimeError("Install the official sentry-cli before uploading symbols.")
    config = json.loads((root / "Sources/Resources/SentryConfiguration.json").read_text())
    if config.get("appIdentifier") != "com.elixirevo.PinShot":
        raise RuntimeError("Unexpected Sentry app identifier.")
    environment = os.environ.copy()
    api_url = "https://sentry.io"
    if not environment.get("SENTRY_AUTH_TOKEN"):
        library = Path(os.environ.get("MAC_APP_ESSENTIALS_PATH", str(root.parent / "tools/library")))
        spec = importlib.util.spec_from_file_location("sentry_setup", library / "scripts/sentry-setup.py")
        setup = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(setup)
        profile = setup.validate_profile(json.loads(setup.PROFILE.read_text()))
        if profile["organization"] != config["organization"]:
            raise RuntimeError("Developer profile and app Sentry organizations differ.")
        environment["SENTRY_AUTH_TOKEN"] = setup.token_from_keychain(profile["keychainService"], profile["keychainAccount"])
        api_url = setup.api_base(profile["apiBase"]).removesuffix("/api/0/")
    # Tokens travel only through the child environment, never command arguments or resources.
    environment["SENTRY_LOG_LEVEL"] = "info"
    environment["SENTRY_DISABLE_UPDATE_CHECK"] = "1"
    result = subprocess.run([cli, "--url", api_url, "debug-files", "upload",
        "--org", config["organization"], "--project", config["project"],
        "--type", "dsym", "--no-sources", "--wait-for", "60", *map(str, paths)], env=environment)
    return result.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Authentication helpers and malformed configuration must not leak credential details.
        print("Sentry symbol upload failed. Check dSYM paths, sentry-cli and the developer profile or CI token.", file=sys.stderr)
        sys.exit(1)
