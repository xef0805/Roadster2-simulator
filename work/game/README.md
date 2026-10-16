# Roadster Flight Lab 源工程

使用 Godot 4.7.2 标准版导入本目录 project.godot，按 F5 运行。物理引擎为 Jolt，固定 120Hz。Windows 导出需安装对应版本标准导出模板。

项目仓库：https://github.com/xef0805/Roadster2-simulator 。作者水印：GitHub https://github.com/xef0805 / 抖音 Felix_0805。详细操作见「操作说明.md」。

- main.gd：场地、镜头、界面、独立运行验证。
- car.gd：驾驶物理、近地升力、喷气特效、音效与实时驾驶舱后视镜。
- art.gd：车辆、机器人和场地建模。
- hud.gd：仪表、世界姿态球与喷口图。
- replay.gd：助跑与爬坡完整记录、轨迹插值、自由镜头与闲置隐藏界面。

在本目录运行（Godot 替换为本机引擎路径）：

```text
Godot --headless --path . --fixed-fps 120 --script res://tests/replay_test.gd
Godot --headless --path . --fixed-fps 120 --script res://tests/physics_test.gd
Godot --headless --path . --fixed-fps 120 --script res://tests/ground_jet_test.gd
Godot --path . -- --qa-current
```

其余 tests/ 下检查覆盖驾驶、滑行、制动、弹道与 HUD。--fixed-fps 可分别设为 30 / 60 / 120。qa-current 生成实际截图与回放、全屏、喷气验证报告，写入游戏用户数据目录。
