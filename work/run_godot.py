"""Run the project with development caches confined to this workspace."""
import os
from pathlib import Path
import subprocess
import shutil
import sys

root = Path(__file__).resolve().parent
game_env = os.environ.copy()
for key, folder in [("APPDATA", "runtime-data"), ("LOCALAPPDATA", "runtime-cache")]:
    location = root / folder
    location.mkdir(exist_ok=True)
    game_env[key] = str(location)
engine = os.environ.get("GODOT_BIN") or str(root / "engine" / "Godot_v4.7.2-stable_win64_console.exe")
if not Path(engine).is_file():
    engine = shutil.which("godot") or shutil.which("godot4")
if not engine:
    raise SystemExit("请安装 Godot 4.7.2，设置 GODOT_BIN 为引擎可执行文件路径。")
if "--export-release" in sys.argv or "--export-debug" in sys.argv:
    templates = root / "runtime-data/Godot/export_templates/4.7.2.stable"
    installed = Path(os.environ.get("APPDATA", "")) / "Godot/export_templates/4.7.2.stable"
    for name in ["windows_debug_x86_64.exe", "windows_release_x86_64.exe"]:
        origin = next((base / name for base in [root / "engine", installed] if (base / name).is_file()), None)
        target = templates / name
        if origin and not target.exists():
            templates.mkdir(parents=True, exist_ok=True)
            try:
                os.link(origin, target)
            except OSError:
                shutil.copyfile(origin, target)
sys.exit(subprocess.run([str(engine), "--path", str(root / "game"), *sys.argv[1:]], env=game_env).returncode)
