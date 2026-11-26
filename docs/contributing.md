# Contributing To BrewStore

[Report A Bug](https://github.com/AMFI-Disable/BrewStore/issues/new?title=%5BBUG%5D+&body=%23%23+Environment+%2F+%E8%BF%90%E8%A1%8C%E7%8E%AF%E5%A2%83%0A%0A%23%23+Steps+To+Reproduce+%2F+%E5%A4%8D%E7%8E%B0%E6%AD%A5%E9%AA%A4%0A%0A%23%23+Expected+And+Actual+Results+%2F+%E9%A2%84%E6%9C%9F%E4%B8%8E%E5%AE%9E%E9%99%85%E7%BB%93%E6%9E%9C%0A%0A) · [Request A Feature](https://github.com/AMFI-Disable/BrewStore/issues/new?title=%5BFEATURE%5D+&body=%23%23+User+Need+%2F+%E4%BD%BF%E7%94%A8%E9%9C%80%E6%B1%82%0A%0A%23%23+Proposed+Change+%2F+%E6%94%B9%E8%BF%9B%E6%96%B9%E6%A1%88%0A%0A%23%23+Acceptance+Criteria+%2F+%E9%AA%8C%E6%94%B6%E6%9D%A1%E4%BB%B6%0A%0A)

[中文贡献指南](contributing.zh-cn.md)

Thank you for your interest in contributing to BrewStore! As an open-source utility, we welcome community improvements, bug fixes, and feature contributions.

## Development Setup

To build and run the BrewStore project locally:

1. **Prerequisites**: Ensure you have macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:

   ```bash
   brew install xcodegen
   ```

2. **Generate Xcode Project**: Generate the project file from our declarative specification (`project.yml`):

   ```bash
   xcodegen generate
   ```

3. **Open Xcode**: Open the generated project bundle:

   ```bash
   open BrewStore.xcodeproj
   ```

4. **Compile & Run**: Press `Cmd + R` inside Xcode to build and launch the application locally.

## Development Guidelines

- **File/Folder Naming**: All files and folders in the repository must be strictly named in **lowercase**.
- **Commit Messages**: Strictly adhere to the canonical commit structure `xxx: xxx xxx xxx` (prefix + exactly three lowercase words, e.g. `feat: add search filter`, `fix: resolve runtime warnings`, `docs: update setup guide`).
- **Formatting**: Run `swiftformat .` to maintain code formatting consistency.
- **Testing**: Verify your changes build cleanly and run unit tests (`Cmd + U` in Xcode) before opening a Pull Request.

Please make sure to review our [Security Policy](../security.md) before submitting contributions.
