# 下载、安全与隐私说明

## 官方下载与来源核验

- 唯一维护仓库：https://github.com/xef0805/Roadster2-simulator
- 正式下载：https://github.com/xef0805/Roadster2-simulator/releases
- 公开构建：https://github.com/xef0805/Roadster2-simulator/actions/workflows/build.yml
- 每个采用新流程的版本附带 `SHA256SUMS.txt`、`Build-info.json`、Defender 扫描原始记录和自动检查报告。

`Build-info.json` 指明准确源码提交、构建运行链接及文件 SHA-256。构建使用 GitHub 标准 Windows 托管环境；Godot 编辑器和导出模板来自官方发布，下载后校验固定 SHA-256。自动构建不从维护者电脑提取二进制。

在解压目录打开 PowerShell，检查游戏本体：

```powershell
Get-FileHash -LiteralPath '.\RoadsterLab\RoadsterLab.exe' -Algorithm SHA256
```

将结果与同一发布页的 `SHA256SUMS.txt` 对应行比较。压缩包也可用相同命令核对。校验值只能帮助确认完整性，不能独立证明程序安全。

有 GitHub CLI 的用户还可验证构建来源证明：

```powershell
gh attestation verify '.\RoadsterLab\RoadsterLab.exe' --repo xef0805/Roadster2-simulator
```

构建来源证明与 Windows 数字签名是不同机制，不会让 SmartScreen 自动放行。

## 首次启动与 Windows 提示

完整解压 `RoadsterLab-Windows.zip`，双击 `RoadsterLab/RoadsterLab.exe`。本程序当前没有受信任的 Windows 代码签名，新下载文件可能出现“Windows 已保护你的电脑”。只有确认下载来自上述仓库且校验值一致后，再决定是否通过“更多信息”查看应用并选择“仍要运行”。无需关闭杀毒、防火墙或安装来历不明的根证书。组织管理设备可能不允许放行，应遵守设备管理策略。

## 权限、联网与本地数据

以下说明基于仓库游戏代码与项目设置的检查，不是独立第三方安全审计：

- 游戏为离线单机，不含登录、广告、遥测、自动更新或联网通信代码。
- 不需要管理员权限，不安装服务、不添加开机启动项、不修改注册表。
- 不访问设备摄像头；场景中的镜头均为游戏虚拟镜头。项目关闭麦克风输入；回放声音来自游戏音效。
- 最近一次动作回放保存在本次进程内存中，退出游戏后不保留，不读取个人文档或浏览器数据。
- Godot 默认可在 `%APPDATA%\Godot\app_userdata\Roadster Flight Lab\` 写入运行日志。维护者主动使用 `--qa-*` 验证参数时，也会在该目录写入游戏截图、游戏输出声音采样及检查记录；这不是桌面录屏或麦克风录音。
- 应用以 MIT 许可证公开源码，Godot 及组件许可证随包提供。

删除解压后的游戏目录即可移除程序；如需清除日志，可另行删除上述应用专属数据目录。不要删除整个 Godot 用户数据目录，以免影响其他游戏。

## 检测结果的边界

Defender 原始报告记录扫描器、病毒库版本、扫描时间、文件哈希与退出码；`passed` 表示当次指定文件扫描完成且未报告威胁，`unavailable` 表示扫描器不可用，不能当作通过。任何扫描结果、公开源码或来源证明都不构成绝对安全保证。

如发布页提供 VirusTotal 链接，应打开对应文件哈希的原始报告核对检测时间。没有实际报告时不宣称“多引擎检测通过”。

## Code signing policy

当前发布文件未进行 Windows Authenticode 代码签名。维护者为 [xef0805](https://github.com/xef0805)，负责代码、构建审阅与正式发布。没有使用自签名证书冒充可信发布者，也未获得 SignPath Foundation 的签名批准。未来如通过公益签名审核，会在这里公开提供者、签名者与审批流程。

## 报告问题

一般运行问题请提交 [Issue](https://github.com/xef0805/Roadster2-simulator/issues)。涉及漏洞或隐私的数据请通过仓库 Security 页的私密漏洞报告渠道提交，避免在公开 Issue 贴个人资料。
