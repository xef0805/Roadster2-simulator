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
shutil.copy2(data / "current_replay_audio.wav", qa)
for name in ["current-visual-report.json", "performance.json", "performance.png", "performance-cockpit.json", "performance-cockpit.png"]:
    shutil.copy2(data / name, qa)
shutil.copy2(data / "v014_720p.png", qa / "720p.png")
for file in (root / "work/checks").iterdir():
    shutil.copy2(file, qa)
for mode in ["current", "perf", "perf-cockpit", "small"]:
    shutil.copy2(root / f"work/standalone-{mode}.log", qa)
shutil.copy2(data / "current_model_front.png", out / "截图_Roadster.png")
shutil.copy2(data / "current_replay_front.png", out / "截图_回放.png")
shutil.copy2(data / "current_model_side.png", out / "截图_侧面.png")
shutil.copy2(data / "current_landing_cloud.png", out / "截图_落地喷气.png")
perf = json.loads((data / "performance.json").read_text(encoding="utf-8"))
visual = json.loads((data / "current-visual-report.json").read_text(encoding="utf-8"))
summary = json.loads((qa / "summary.json").read_text(encoding="utf-8"))
cockpit_perf = json.loads((data / "performance-cockpit.json").read_text(encoding="utf-8"))
assert all(row["passed"] for row in summary) and visual["passed"]
(qa / "验证记录.md").write_text(f"""# v1.0.0 首个正式版验证记录

- 30 / 60 / 120 FPS 各通过 {sum(row['checks'] for row in summary if row['display_fps']==120)} 项检查，共 {sum(row['checks'] for row in summary)} 项。包含倒挂路线和五车飞越各连续三次、弹道、吸附、漂移、制动、仪表，以及 {next(row['checks'] for row in summary if row['suite']=='replay_test')} 项回放/高空喷气检查。
- 高空按空格：4 个主喷口有动画，垂直推力为 0，无近地白雾。独立版截图与原始报告在本目录。
- 实际默认启动为全屏模式 {visual['window_mode']}、无边框 {visual['borderless']}，屏幕 {visual['screen_size']}。另以 1280×720 窗口检查布局。
- 回放从实际起跳和横滚录得 {visual['clip_frames']} 帧、{visual['clip_seconds']:.2f} 秒，30Hz 采样、逐帧插值显示。检查暂停、时间轴边界、自由镜头、重置不覆盖上一次录像，返回驾驶时原位置误差 {visual['restored_position_error']:.8f} 米，速度恢复检查通过。
- 真实驾驶检查确认坡道录像第一帧位于平地起点 (-42,约0.516,22)，包含助跑、接触坡面爬升、倒挂、飞行和落地，约 363 帧。缓冲最长 12 秒，整段上限约 120 秒；静止停车时仅留约 1 秒准备画面。
- 回放默认速度 32m/s，Shift 三倍。空格播放/暂停，左右箭头前后跳一秒，Q/E 世界坐标升降，鼠标上下方向修正；这些输入不操作原车。默认镜头跟随车辆，操作后自由观察。
- 独立版实际渲染检查：静置后界面保持显示，点击隐藏按钮后提示、标题、仪表和进度条隐藏，水印保留；普通输入保持隐藏，H 恢复，R 从头重播。驾驶车外/驾驶舱及回放的上下拖动反转检查通过。移除 Landing Zone 文字与绿色边框，后视镜保持原样。
- 银灰金属车漆、圆润的 40 点横截面、连续插值的车身及车顶曲面，移除侧面黑色装饰片。侧窗不透明，主镜头排除机器人；后视镜保持原样。已查看车身前后、侧面、镜内画面和暂停菜单。
- 回放声音来自录像中的速度、轮胎滑动、喷气与落地状态，原车在回放时静音。实际音频输出 RMS {visual['replay_audio_rms']:.8f}，暂停时 RMS {visual['replay_paused_audio_rms']:.8f}；音频采样见 current_replay_audio.wav。另检查落地声连续播放触发、拖动进度不误触发、重播从头开始。
- 落地缓冲喷流加宽加密，白雾集中在车身附近：雾团尺寸、径向扩散速度与存留时间均缩小。实机下降时白雾发射比例 {visual['landing_fog_ratio']:.2f}，高空不发射贴地雾；current_landing_plume.png / current_landing_cloud.png 展示接地前后效果。物理推力不变。
- 已查看近地雾、高空气柱、横滚、回放及自由镜头。车辆为简化模型，非官方精确模型；烟雾重新生成，不逐粒录制。
- 独立 Windows exe 从不含源工程的目录启动完成验证，退出码均为 0，无脚本错误。
- {perf['renderer']}，实际图像 {perf['render_resolution']}，短时基准平均 {perf['average_fps']:.1f} FPS，P95 {perf['p95_frame_ms']:.2f}ms。解除帧率限制的样本超过 60FPS 目标；普通游戏封顶 120FPS，该样本不代表所有场景最低帧率。
- 驾驶舱含实时后视镜的独立 1080p 样本：平均 {cockpit_perf['average_fps']:.1f} FPS，P95 {cockpit_perf['p95_frame_ms']:.2f}ms。

所有动作均由自动输入验证，没有宣称人工逐关试玩。日志中的系统证书库提示未影响离线运行，高速无头测试偶有 Jolt 队列警告。项目使用固定工程、发布、压缩包和验证目录，之后覆盖更新。GitHub 上传与下载包校验结果见 GitHub发布记录.json。
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
