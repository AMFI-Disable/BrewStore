# Contributing to BrewStore

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
- **Commit Messages**: Follow standard commit prefixes (e.g. `feat: add ...`, `fix: resolve ...`, `style: format ...`).
- **Formatting**: Run `swiftformat .` to maintain code formatting consistency.
- **Testing**: Verify your changes build cleanly and run unit tests (`Cmd + U` in Xcode) before opening a Pull Request.

Please make sure to review our [Security Policy](../security.md) before submitting contributions.
