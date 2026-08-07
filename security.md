# Security Policy

BrewStore executes Homebrew commands locally and can move selected application files to the macOS Trash. It does not silently install software, collect telemetry, or upload command output.

Please report vulnerabilities privately through the Juicer project’s security reporting process. Include the BrewStore version, macOS version, reproduction steps, and whether the issue involves Homebrew command execution, path validation, or removal behavior. Do not include credentials, private logs, or personal file contents in a report.

The first release intentionally limits removal to Homebrew-installed casks and requires a preview before leftover files are moved.
