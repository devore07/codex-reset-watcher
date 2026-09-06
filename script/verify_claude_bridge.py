#!/usr/bin/env python3
"""Exercise the packaged helper with synthetic data and isolated settings only."""
import base64
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import tempfile
import time


def verify(helper):
    with tempfile.TemporaryDirectory(prefix="claude bridge 'test' ") as temporary:
        directory = Path(temporary)
        settings = directory / "settings.json"
        state_file = directory / "connection.json"
        command = f"{shlex.quote(str(helper))} --directory {shlex.quote(str(directory))}"
        settings.write_text(json.dumps({"statusLine": {"type": "command", "command": command}}))
        state = {"enabled": True, "configurationPath": str(settings), "wrapperCommand": command}

        def save_state(previous=None):
            if previous is None:
                state.pop("previousStatusLine", None)
            else:
                state["previousStatusLine"] = base64.b64encode(json.dumps({"type": "command", "command": previous}).encode()).decode()
            state_file.write_text(json.dumps(state))

        payload = json.dumps({
            "transcript_path": "DO_NOT_PERSIST_THIS_SENTINEL",
            "rate_limits": {
                "five_hour": {"used_percentage": 23.5, "resets_at": time.time() + 3600},
                "seven_day": {"used_percentage": 60, "resets_at": time.time() + 86400},
            },
        }).encode()

        def run(data=payload):
            return subprocess.run(["/bin/sh", "-c", command], input=data, capture_output=True, timeout=10)

        save_state()
        result = run(b"{}")
        assert result.stdout == b"Waiting for Claude usage\n"
        assert json.loads((directory / "usage.json").read_bytes())["waitingForUsage"] is True
        result = run()
        assert result.returncode == 0, result.stderr
        assert result.stdout == b"5h: 76% remaining | Week: 40% remaining\n"
        report_file = directory / "usage.json"
        report = json.loads(report_file.read_bytes())
        assert report["fiveHour"]["usedPercentage"] == 23.5
        assert "DO_NOT_PERSIST_THIS_SENTINEL" not in report_file.read_text()
        assert stat.S_IMODE(report_file.stat().st_mode) == 0o600

        save_state("cat")
        result = run()
        assert result.stdout == payload, "Previous command did not receive identical input"
        assert result.returncode == 0
        result = run(b"not JSON; DO_NOT_PERSIST_THIS_SENTINEL")
        assert result.stdout == b"not JSON; DO_NOT_PERSIST_THIS_SENTINEL"
        assert "fiveHour" not in json.loads(report_file.read_bytes())

        save_state("printf 'original output'; exit 7")
        result = run(b"x" * 1_048_576)
        assert result.stdout == b"original output"
        assert result.returncode == 7

        save_state()
        with ThreadPoolExecutor(max_workers=8) as executor:
            results = list(executor.map(lambda _: run(), range(32)))
        assert all(result.returncode == 0 for result in results)
        assert json.loads(report_file.read_bytes())["sevenDay"]["usedPercentage"] == 60

        before = report_file.read_bytes()
        state["enabled"] = False
        save_state("cat")
        result = run()
        assert result.stdout == payload
        assert report_file.read_bytes() == before, "Disconnected helper wrote a report"
        state["enabled"] = True
        save_state("cat")
        settings.write_text(json.dumps({"statusLine": {"type": "command", "command": "printf replacement"}}))
        run()
        assert report_file.read_bytes() == before, "Replaced configuration still recorded data"


if __name__ == "__main__":
    verify(Path(sys.argv[1]).resolve(strict=True))
    print("Claude bridge verification passed: forwarding, privacy, permissions, concurrency, disconnect.")
