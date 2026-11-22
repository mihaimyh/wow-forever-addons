# WoW: Forever AddOns (Interface 16001)

Shared repository for custom World of Warcraft: Forever (Classic+) addons:

- **RetPulse** — Retribution Paladin rotation advisor, Unsealed Wrath echo tracker, weapon-speed seal pairing, keybind badges, and 60 FPS dark-glass HUD.
- **ChatCopy** — Lightweight, secret-safe chat copy button and `/copy` popup window.

## Local Setup (Windows Junctions)

Both addon folders are linked directly into `World of Warcraft\_forever_\Interface\AddOns\` via Windows Directory Junctions so edits here take effect immediately on `/reload`.

## Running RetPulse Offline Tests

```powershell
cd RetPulse
npx --yes --package=fengari-node-cli fengari tests/run_tests.lua
```
