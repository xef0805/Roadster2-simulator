from pathlib import Path
import hashlib
import json
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent
out = root / "outputs"
release = out / "RoadsterLab"
source = out / "RoadsterLab-source"
qa = out / "验证资料"
game = root / "work/game"
data = root / "work/release-data/Godot/app_userdata/Roadster Flight Lab"
qa.mkdir(exist_ok=True)
for name in ["操作说明.md", "LICENSE", "GODOT-LICENSES.txt"]:
    shutil.copy2(game / name, release / name)
shutil.copytree(game, source, ignore=shutil.ignore_patterns(".godot", "export_templates", "feature_profiles", "script_templates", "text_editor_themes"), dirs_exist_ok=True)
preset = source / "export_presets.cfg"
preset.write_text(preset.read_text(encoding="utf-8").replace("../../outputs/RoadsterLab/", "../RoadsterLab/"), encoding="utf-8")
for file in data.glob("current_*.png"):
    shutil.copy2(file, qa)
for name in ["current-visual-report.json", "performance.json", "performance.png"]:
    shutil.copy2(data / name, qa)
shutil.copy2(data / "v014_720p.png", qa / "720p.png")
for file in (root / "work/checks").iterdir():
    shutil.copy2(file, qa)
for mode in ["current", "perf", "small"]:
    shutil.copy2(root / f"work/standalone-{mode}.log", qa)
shutil.copy2(data / "current_model_front.png", out / "截图_Roadster.png")
shutil.copy2(data / "current_replay_front.png", out / "截图_回放.png")
perf = json.loads((data / "performance.json").read_text(encoding="utf-8"))
visual = json.loads((data / "current-visual-report.json").read_text(encoding="utf-8"))
summary = json.loads((qa / "summary.json").read_text(encoding="utf-8"))
assert all(row["passed"] for row in summary) and visual["passed"]
(qa / "验证记录.md").write_text(f"""# v0.1.6 验证记录

- 30 / 60 / 120 FPS 各通过 78 项检查，共 {sum(row['checks'] for row in summary)} 项。包含倒挂路线和五车飞越各连续三次、弹道、吸附、漂移、制动、仪表，以及新增的 15 项回放/高空喷气检查。
- 高空按空格：4 个主喷口有动画，垂直推力为 0，无近地白雾。独立版截图与原始报告在本目录。
- 实际默认启动为全屏模式 {visual['window_mode']}、无边框 {visual['borderless']}，屏幕 {visual['screen_size']}。另以 1280×720 窗口检查布局。
- 回放从实际起跳和横滚录得 {visual['clip_frames']} 帧、{visual['clip_seconds']:.2f} 秒，30Hz 采样、逐帧插值显示。检查暂停、时间轴边界、自由镜头、重置不覆盖上一次录像，返回驾驶时原位置误差 {visual['restored_position_error']:.8f} 米，速度恢复检查通过。
- 已查看实际渲染的车身前后、驾驶舱、近地雾、高空气柱、横滚、回放及自由镜头画面。车辆为简化模型，非官方精确模型；烟雾重新生成，不逐粒录制。
- 独立 Windows exe 从不含源工程的目录启动完成验证，退出码均为 0，无脚本错误。
- {perf['renderer']}，实际图像 {perf['render_resolution']}，短时基准平均 {perf['average_fps']:.1f} FPS，P95 {perf['p95_frame_ms']:.2f}ms。解除帧率限制的样本超过 60FPS 目标；普通游戏封顶 120FPS，该样本不代表所有场景最低帧率。

所有动作均由自动输入验证，没有宣称人工逐关试玩。日志中的系统证书库提示未影响离线运行，高速无头测试偶有 Jolt 队列警告。项目已改用固定工程、发布、压缩包和验证目录，之后覆盖更新。
""", encoding="utf-8")
for folder, filename in [(release, "RoadsterLab-Windows.zip"), (source, "RoadsterLab-source.zip")]:
    target = out / filename
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for file in folder.rglob("*"):
            if file.is_file(): archive.write(file, file.relative_to(out))
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        if folder==release:
            assert hashlib.sha256(archive.read("RoadsterLab/RoadsterLab.exe")).digest()==hashlib.sha256((release / "RoadsterLab.exe").read_bytes()).digest()
    print(filename, target.stat().st_size, "bytes; verified")
for name in ["main.gd", "car.gd", "art.gd", "hud.gd", "replay.gd"]:
    assert (source / name).read_bytes()==(game / name).read_bytes()
print("Latest fixed delivery updated")
