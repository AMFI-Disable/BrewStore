export const siteConfig = {
  "title": "BrewStore",
  "repoUrl": "https://github.com/AMFI-Disable/BrewStore",
  "category": "macOS Native App",
  "accent": "#2EA3F2",
  "tagline": "Lightning-fast, native SwiftUI graphical package manager and CLI companion for Homebrew.",
  "primaryCta": {
    "label": "Download DMG (v1.0.0)",
    "href": "./downloads/brewstore-1.0.0.dmg"
  },
  "secondaryCta": {
    "label": "View on GitHub",
    "href": "https://github.com/AMFI-Disable/BrewStore"
  },
  "quickCmd": "brew tap AMFI-Disable/brewstore && brew install --cask brewstore",
  "features": [
    {
      "title": "Casks, Formulae & Services",
      "desc": "Browse, install, upgrade, and manage GUI casks, CLI formulae, and background brew services from a native App Store-style UI."
    },
    {
      "title": "Sub-20ms Tokenized Search",
      "desc": "In-memory indexed catalog searches thousands of Homebrew packages instantaneously as you type."
    },
    {
      "title": "Rollback Time Machine",
      "desc": "Snapshot installed package states and restore previous versions or pin formulae to prevent unwanted upgrades."
    },
    {
      "title": "Mirror Speed Benchmark",
      "desc": "Test and switch between Homebrew CDN mirrors with real-time latency and throughput measurements."
    },
    {
      "title": "Menu Bar & CLI Companion",
      "desc": "Monitor outdated packages from the macOS menu bar or trigger diagnostics from the companion CLI."
    },
    {
      "title": "Zero Telemetry",
      "desc": "Runs strictly against your local Homebrew installation with zero external tracking."
    }
  ],
  "steps": [
    {
      "title": "Tokenized Catalog Sync",
      "desc": "Parses local Homebrew JSON metadata into a fast, searchable index in under 20ms."
    },
    {
      "title": "Dry-Run Lock Queue",
      "desc": "Serializes install, upgrade, and uninstall operations with dependency previews and conflict checks."
    },
    {
      "title": "Atomic State Snapshots",
      "desc": "Records pre-change Brewfiles so you can roll back package versions anytime."
    }
  ],
  "installCmds": [
    {
      "label": "Homebrew Cask (Recommended)",
      "cmd": "brew tap AMFI-Disable/brewstore && brew install --cask brewstore"
    },
    {
      "label": "Direct DMG Download",
      "cmd": "curl -LO https://amfi-disable.github.io/BrewStore/downloads/brewstore-1.0.0.dmg"
    }
  ],
  "requirements": [
    "macOS 14.0+ (Sonoma / Sequoia)",
    "Homebrew installed",
    "345 / 345 automated tests passing"
  ]
} as const;
