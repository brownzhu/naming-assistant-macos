# Contributing

请先阅读 README、SECURITY.md 和 ROADMAP.md。当前维护目标是 `NamingAssistant`，保留的 Quick Rename GUI/CLI 属于上游源码。

```bash
swift build --build-system native --product NamingAssistant
bash scripts/test-naming-safety.sh
```

- 文件系统测试只能使用隔离的虚构样例，不改开发者真实文件。
- 命名建议与文件操作分层；新 UI 必须通过 `SafeRenameCoordinator`，不能直接调用旧 `FileRenamer` 绕过保护。
- 不自动上传文件内容、不接入付费服务、不执行模型输出，不把时间戳自动视为资料日期。
- 修改执行/撤销边界时增加针对失败行为的回归；不可用/不确定必须如实展示。
- 新图表和截图仅使用虚构对象；不要提交个人路径、日志、密钥、用户数据、构建目录或应用包。
- 问题报告应区分期望、实际、系统/工具链版本；计划功能不可写为已实现。
- CI 的命令行通过不等于 GUI、所有系统版本或本机模型质量已验收。

若打算贡献旧产品目标，请在 PR 中明确范围，不把原产品能力写入当前应用的说明。
