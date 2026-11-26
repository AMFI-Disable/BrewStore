# 参与 BrewStore 开发

[报告缺陷](https://github.com/AMFI-Disable/BrewStore/issues/new?title=%5BBUG%5D+&body=%23%23+Environment+%2F+%E8%BF%90%E8%A1%8C%E7%8E%AF%E5%A2%83%0A%0A%23%23+Steps+To+Reproduce+%2F+%E5%A4%8D%E7%8E%B0%E6%AD%A5%E9%AA%A4%0A%0A%23%23+Expected+And+Actual+Results+%2F+%E9%A2%84%E6%9C%9F%E4%B8%8E%E5%AE%9E%E9%99%85%E7%BB%93%E6%9E%9C%0A%0A) · [提出功能建议](https://github.com/AMFI-Disable/BrewStore/issues/new?title=%5BFEATURE%5D+&body=%23%23+User+Need+%2F+%E4%BD%BF%E7%94%A8%E9%9C%80%E6%B1%82%0A%0A%23%23+Proposed+Change+%2F+%E6%94%B9%E8%BF%9B%E6%96%B9%E6%A1%88%0A%0A%23%23+Acceptance+Criteria+%2F+%E9%AA%8C%E6%94%B6%E6%9D%A1%E4%BB%B6%0A%0A)

[English](contributing.md) · [项目文档](../readme.zh-cn.md)

## 开发环境

使用 macOS 14 或更新版本、Xcode 15 或更新版本以及 XcodeGen。在项目根目录执行：

```bash
brew install xcodegen
xcodegen generate
open BrewStore.xcodeproj
```

在 Xcode 中按 Command-R 启动应用，按 Command-U 运行测试。

## 提交与验证

文件和目录使用小写。遵循现有的 SwiftFormat 配置，执行 `swiftformat .` 并检查格式差异。提交说明采用 `type: three lowercase words` 格式，例如 `feat: add search filter`。发起拉取请求前请确认构建和测试通过，并在验证结果中记录使用的 macOS 和 Xcode 版本。

安全问题请遵循[安全策略](../security.md)中的报告流程。
