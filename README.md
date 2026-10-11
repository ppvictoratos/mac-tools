# mac-tools

A modular Mac maintenance toolkit for developers who don't want to think about disk space.

Computing generates a lot of unintended files, intended caches, and invisible bloat — sometimes just called "System Data." I got into the routine of hunting these down after shipping a product or finishing a heavy dev session, so I built a script to handle it. It started as a quarterly cron job. Now I just run it whenever storage gets too close to full.

Built for a MacBook Air with "256" GB. Keeping it light is essential.

---

## Modules

| Module | What it does |
|---|---|
| **Cleanup** | Deep clean — Mail archives, user caches, Xcode/Developer data, Time Machine snapshots |
| **Quarterly** | Routine maintenance — npm cache, old node_modules, VS Code cache, trash, git status check |
| **Organize** | Sort home-directory projects into `~/work`, `~/personal`, `~/archive` |
| **Setup** | Full dev environment bootstrap — Homebrew, Node (nvm), Ruby, Python packages, shell config |

---

## Usage

```bash
# Interactive menu
bash mac_tools.sh

# Run a module directly
bash mac_tools.sh cleanup
bash mac_tools.sh quarterly
bash mac_tools.sh organize
bash mac_tools.sh setup
```

Every destructive operation prompts for confirmation before running. Logs are saved to `~/mac_tools_<timestamp>.log`.

---

## What it cleans

- `~/Library/Caches` — app caches (Spotify, Chrome, Playwright, etc.)
- `~/Library/Developer` — Xcode DerivedData, iOS DeviceSupport, CoreSimulator devices
- Mail Import archives and download cache
- Time Machine local snapshots
- Old `node_modules` folders (90+ days untouched)
- VS Code cached data
- Font and DNS caches

---

## Safety

- All `rm` operations are gated behind `y/n` prompts
- Variables are quoted and guarded (`${VAR:?}`) to prevent glob expansion accidents
- `sudo` is used only for font caches, DNS flush, and Time Machine snapshots
- Existing files (e.g. `~/.gitignore_global`) are backed up before overwriting
- Logs every action to a timestamped file in `~`

---

## Requirements

- macOS (tested on Apple Silicon, macOS 26)
- Bash 3.2+
- Xcode Command Line Tools (for the Setup module)

---

## Notes

The **Setup** module is opinionated — it installs my personal Homebrew formula list, Node versions, and shell config. Fork and edit `FORMULAE`, `CASKS`, and the `~/.zshrc` entries to match your stack before running it.

AWS credentials are never written by the script. The config sets region only; credentials must be copied manually from a secure source.

---

## Media

<img width="3132" height="1566" alt="mac-tools-combined" src="https://github.com/user-attachments/assets/57f4d4bd-a35a-485a-a3b8-457423af0b5b" />


