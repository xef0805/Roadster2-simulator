"""Public Windows build: verified upstream tools, source export and provenance metadata."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "outputs"
GAME = ROOT / "work/game"
ENGINE = ROOT / "work/engine"
VERSION = "4.7.2"
DOWNLOADS = {
    "Godot_v4.7.2-stable_win64.exe.zip": "731980f9608d61333e5baf54a2ef17210acc7a538446c0cb9969f002aca1e953",
    "Godot_v4.7.2-stable_export_templates.tpz": "f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011",
}


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def setup():
    ENGINE.mkdir(parents=True, exist_ok=True)
    for name, expected in DOWNLOADS.items():
        target = ENGINE / name
        url = f"https://github.com/godotengine/godot-builds/releases/download/{VERSION}-stable/{name}"
        print("Download official tool", name, flush=True)
        urllib.request.urlretrieve(url, target)
        if digest(target) != expected:
            raise RuntimeError("Official Godot download checksum mismatch: " + name)
        print("SHA-256 verified", name, expected, flush=True)
        with zipfile.ZipFile(target) as archive:
            for member in archive.namelist():
                filename = Path(member).name
                if filename in {"Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win64_console.exe", "windows_debug_x86_64.exe", "windows_release_x86_64.exe"}:
                    with archive.open(member) as source, (ENGINE / filename).open("wb") as output:
                        shutil.copyfileobj(source, output)
    (OUT / "RoadsterLab").mkdir(parents=True, exist_ok=True)


def smoke():
    env = os.environ.copy()
    env["APPDATA"] = str(ROOT / "work/ci-runtime")
    env["LOCALAPPDATA"] = str(ROOT / "work/ci-cache")
    empty = ROOT / "work/ci-launch"
    empty.mkdir(parents=True, exist_ok=True)
    log = ROOT / "work/ci-launch.log"
    result = subprocess.run([str(OUT / "RoadsterLab/RoadsterLab.exe"), "--headless", "--quit-after", "120", "--log-file", str(log)], cwd=empty, env=env, timeout=60)
    text = log.read_text(encoding="utf-8", errors="replace")
    print(text)
    if result.returncode or "SCRIPT ERROR" in text:
        raise RuntimeError("Independent executable launch failed")


def archive_folder(folder, target):
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(folder.rglob("*")):
            if path.is_file():
                info = zipfile.ZipInfo(path.relative_to(OUT).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes())
    with zipfile.ZipFile(target) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Invalid release ZIP")


def package():
    summary = json.loads((ROOT / "work/checks/summary.json").read_text(encoding="utf-8"))
    if not summary or not all(row["passed"] for row in summary):
        raise RuntimeError("Automated checks did not pass")
    release = OUT / "RoadsterLab"
    source = OUT / "RoadsterLab-source"
    for name in ["操作说明.md", "LICENSE", "GODOT-LICENSES.txt"]:
        shutil.copy2(GAME / name, release / name)
    shutil.copy2(ROOT / "SECURITY.md", release / "安全与隐私说明.md")
    shutil.copytree(GAME, source, ignore=shutil.ignore_patterns(".godot", "export_templates", "feature_profiles", "script_templates", "text_editor_themes"), dirs_exist_ok=True)
    shutil.copy2(ROOT / "SECURITY.md", source / "安全与隐私说明.md")
    preset = source / "export_presets.cfg"
    preset.write_text(preset.read_text(encoding="utf-8").replace("../../outputs/RoadsterLab/", "../RoadsterLab/"), encoding="utf-8")
    for folder, name in [(release, "RoadsterLab-Windows.zip"), (source, "RoadsterLab-source.zip")]:
        archive_folder(folder, OUT / name)
    product = re.search(r'application/product_version="([^"]+)"', (GAME / "export_presets.cfg").read_text(encoding="utf-8"))[1]
    info = {
        "repository": "https://github.com/" + os.environ["GITHUB_REPOSITORY"],
        "source_commit": os.environ["GITHUB_SHA"],
        "version": product,
        "workflow_run": f"https://github.com/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ['GITHUB_RUN_ID']}",
        "runner": os.environ.get("RUNNER_OS"),
        "godot_version": VERSION,
        "official_tool_sha256": DOWNLOADS,
        "automated_checks": sum(row["checks"] for row in summary),
        "windows_authenticode": "unsigned",
        "files": {name: digest(OUT / name) for name in ["RoadsterLab/RoadsterLab.exe", "RoadsterLab-Windows.zip", "RoadsterLab-source.zip"]},
    }
    (OUT / "Build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (OUT / "SHA256SUMS.txt").write_text("".join(f"{value}  {name}\n" for name, value in info["files"].items()), encoding="utf-8")
    with zipfile.ZipFile(OUT / "自动测试结果.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((ROOT / "work/checks").iterdir()):
            archive.write(path, path.name)
        archive.write(ROOT / "work/ci-launch.log", "independent-launch.log")
    print(json.dumps(info, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    {"setup": setup, "smoke": smoke, "package": package}[sys.argv[1]]()
