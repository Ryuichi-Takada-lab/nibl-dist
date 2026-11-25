# Nibl

A little wax drop who lives in your MacBook's notch: watches your AI coding agents
(Claude Code, Codex), dances to your music, keeps quick notes and shows your Mac's memory.

Step-by-step guide (in Russian): https://ryuichi-takada-lab.github.io/nibl-dist/

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Ryuichi-Takada-lab/nibl-dist/main/install.sh | bash
```

Needs macOS 15+ on Apple Silicon. Nibl connects Claude Code and Codex by itself if they
are on your Mac; without them you still get music, notes and the monitor.

## Remove

```bash
curl -fsSL https://raw.githubusercontent.com/Ryuichi-Takada-lab/nibl-dist/main/install.sh | bash -s -- --uninstall
```

© 2026 Nibl. All rights reserved. This repository holds only the installer; the app is
distributed as a compiled build under the license shown in the app.
