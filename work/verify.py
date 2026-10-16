from pathlib import Path
import json
import shutil
import subprocess
import sys

work = Path(__file__).resolve().parent
target = work / "checks"
target.mkdir(exist_ok=True)
data = work / "runtime-data/Godot/app_userdata/Roadster Flight Lab"
suites = {
    "ground_jet_test": "ground-jet-report.json",
    "physics_test": "physics-report.json",
    "flight_feedback_test": "flight-feedback-report.json",
    "driving_test": "driving-report.json",
    "hud_test": "hud-report.json",
    "speed_feedback_test": "speed-feedback-report.json",
    "replay_test": "replay-report.json",
}
summary = []
for fps in [30, 60, 120]:
    for script, report in suites.items():
        run = subprocess.run([sys.executable, str(work / "run_godot.py"), "--headless", "--fixed-fps", str(fps), "--script", f"res://tests/{script}.gd"], capture_output=True, text=True, encoding="utf-8", errors="replace")
        (target / f"{script}-{fps}.log").write_text(run.stdout + run.stderr, encoding="utf-8")
        if run.returncode:
            print(run.stdout + run.stderr)
            raise SystemExit(run.returncode)
        result = json.loads((data / report).read_text(encoding="utf-8"))
        assert all(test["passed"] for test in result["tests"]), (script, fps)
        shutil.copy2(data / report, target / f"{script}-{fps}.json")
        entry = {"suite": script, "display_fps": fps, "checks": len(result["tests"]), "passed": True}
        summary.append(entry)
        print(json.dumps(entry), flush=True)
(target / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
print("All checks passed", flush=True)
