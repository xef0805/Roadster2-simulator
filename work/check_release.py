from pathlib import Path
import json
import os
import struct
import subprocess

work = Path(__file__).resolve().parent
exe = work.parent / "outputs/RoadsterLab/RoadsterLab.exe"
empty = work / "standalone-check"
empty.mkdir(exist_ok=True)
env = os.environ.copy()
for key, name in [("APPDATA", "release-data"), ("LOCALAPPDATA", "release-cache")]:
    folder = work / name
    folder.mkdir(exist_ok=True)
    env[key] = str(folder)
for mode in ["current", "perf", "small"]:
    log = work / f"standalone-{mode}.log"
    args = [str(exe), "--log-file", str(log)]
    if mode == "small":
        args += ["--windowed", "--resolution", "1280x720", "--", "--qa-v014-small"]
    else:
        args += ["--", "--qa-" + mode]
    result = subprocess.run(args, cwd=empty, env=env, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=60)
    print(mode, "exit", result.returncode, flush=True)
    assert result.returncode == 0, result.stdout + result.stderr
    text = log.read_text(encoding="utf-8")
    assert "SCRIPT ERROR" not in text
data = work / "release-data/Godot/app_userdata/Roadster Flight Lab"
assert struct.unpack(">II", (data / "current_drive.png").read_bytes()[16:24]) == (1920, 1080)
assert struct.unpack(">II", (data / "v014_720p.png").read_bytes()[16:24]) == (1280, 720)
visual = json.loads((data / "current-visual-report.json").read_text(encoding="utf-8"))
assert visual["passed"]
perf = json.loads((data / "performance.json").read_text(encoding="utf-8"))
assert perf["render_resolution"] == "(1920.0, 1080.0)" or perf["render_resolution"] == "(1920, 1080)"
print(json.dumps(perf), flush=True)
print("Standalone checks passed", flush=True)
