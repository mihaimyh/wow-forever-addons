# AGENTS.md — WoW: Forever AddOns (Interface 16001)

Guidelines for agents building and maintaining addons in this repository (`RetPulse`, `ChatCopy`, and future addons targeting **World of Warcraft: Forever**).

## Repository & Local Workflow

- Each top-level folder (`RetPulse/`, `ChatCopy/`) is a standalone, zero-dependency addon linked via Windows Directory Junctions into `E:\Games\World of Warcraft\_forever_\Interface\AddOns\`.
- Folder name must match `<AddonName>.toc`. Use `## Interface: 16001`.
- New addon folders require returning to Character Select (or restarting WoW); edits to existing files apply on `/reload`.
- Run `RetPulse` offline unit tests from `RetPulse/` before committing:
  ```powershell
  npx --yes --package=fengari-node-cli fengari tests/run_tests.lua
  ```
- Local MCP server (`wow-forever-mcp`, source in `mcp-server/index.mjs`): use `client_status`, `read_saved_vars`, `read_lua_errors`, `search_wow_api`, `read_framexml`, and `validate_addon` when debugging SavedVariables, inspecting exported `16001` API docs, or validating addons.

## WoW: Forever Client Reality (Probed on `1.60.1 build 70938`, TOC `16001`)

WoW: Forever (codename *Camelot*) runs on the **Mainline 12.1.5 UI architecture** and inherits **Midnight's Secret Values restrictions**. Write Mainline 12.x code (`C_Spell`, `C_SpellBook`, `C_UnitAuras`, `C_Item`, `C_Container`, `C_Map`, `C_Timer`, `Settings`), never Classic Era globals (`GetSpellInfo`, `InterfaceOptions_AddCategory`).

- **Flavor check**: `WOW_PROJECT_ID == (WOW_PROJECT_CAMELOT or 18)`. Note that `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE` is `false` on Forever. Prefer feature detection (`if Settings.CreateDropdown then`) over flavor branches.

### Blocked or Secret in Combat (Live-Verified)

| API / Feature | Behaviour on Forever 16001 |
|---|---|
| `COMBAT_LOG_EVENT_UNFILTERED` | Unavailable. Build state machines from unit/cast/swing events instead. |
| `C_UnitAuras.GetAuraDataByIndex` / `GetPlayerAuraBySpellID` | Throws `Auras cannot be accessed when secret while tainted` in combat. Scan player auras only out of combat. |
| `UnitHealth`, `UnitPower`, `UnitAttackSpeed`, `C_Spell.GetSpellCooldown` | Return **secret values** in combat (`type()` still reports `"number"`, but math, comparisons, table keys, and `tostring`/`print` throw). |
| `C_AssistedCombat` | Namespace exists, but `IsAvailable()` returns `false, "WRONG_WORLD_STATE_EXPRESSION"` (disabled on Forever realms). |
| `PlaySoundFile` on interface `.ogg` paths | Unreliable; use `PlaySound(SOUNDKIT.X)`. |

### Readable & Legal in Combat (Live-Verified)

- **Events**: `UNIT_SPELLCAST_SUCCEEDED` (player), `PLAYER_SWING` (`Enum.PlayerSwingType.MainHand`), `UNIT_COMBAT` (target), `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED`, `PLAYER_TARGET_CHANGED`, `PLAYER_LOGOUT`, `COOLDOWN_VIEWER_DATA_LOADED`.
- **Spell state**: `C_Spell.GetSpellIDForSpellIdentifier(name)` + `C_SpellBook.IsSpellKnown(id)` (always resolve by **name** so spell ranks work), `C_Spell.IsSpellUsable(name)` (returns `usable, noMana`; detects execute windows such as `Hammer of Wrath`), `C_Spell.IsSpellInRange(name, "target")`.
- **Melee / unit**: `C_SwingTimer.IsTargetWithinSwingRange(Enum.PlayerSwingType.MainHand)`, `UnitCreatureType("target")`, `UnitClass("player")`, `GetInventoryItemID("player", 16)`.
- **Action bars & bindings**: `GetActionInfo(slot)`, `GetMacroSpell(id)`, `GetBindingKey(cmd)` (rebuild on bar/binding events, never in `OnUpdate`).
- **Native Cooldown Manager**: `C_CooldownViewer` + viewer containers (`BuffIconCooldownViewer`, `BuffBarCooldownViewer`, `EssentialCooldownViewer`, `UtilityCooldownViewer`).
- **Secret-value pass-through**: whitelisted presentation widgets (`StatusBar:SetValue`, `StatusBar:SetMinMaxValues`, `Cooldown:SetCooldownFromDurationObject`) accept secret values directly for visual display without Lua inspecting them.

## Engineering Rules

1. **Guard every untrusted/combat value**: check `issecretvalue(v)` and `issecrettable(v)` before arithmetic, comparison, indexing, `gsub`, or `tostring`.
2. **Preserve last readable values**: when an API turns secret in combat (such as `UnitAttackSpeed`), keep the last readable value instead of overwriting it with `nil`.
3. **Protect frame scans**: check `frame:IsForbidden()` and wrap field reads in `pcall`; scan known Blizzard container frames before touching `UIParent`.
4. **Respect combat lockdown**: queue secure frame creation, movement, show/hide, or attribute changes when `InCombatLockdown()` and flush on `PLAYER_REGEN_ENABLED`.
5. **Zero taint**: use `hooksecurefunc(...)` and `frame:HookScript(...)` instead of replacing Blizzard functions; keep addon state inside `local addonName, ns = ...` (only SavedVariables, slash handlers, and Addon Compartment TOC callbacks may be globals).
6. **Settings & entry points**: register options with `Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnSetting`, and `Settings.CreateCheckbox` / `CreateDropdown` / `CreateSlider`; wrap `CreateSettingsButtonInitializer` in `pcall` (its optional parameters shift across builds). Expose a toggle via TOC `AddonCompartmentFunc` + slash command.
7. **Keep debug telemetry opt-in**: default trace/log flags to `false` and always flush SavedVariables buffers on `PLAYER_LOGOUT`.
8. **Gate class-specific addons early**: check `select(2, UnitClass("player"))` in `ADDON_LOADED` before allocating frames or registering gameplay events.

## Verification Before Finishing

- Every modified Lua file loads cleanly and all offline tests pass (`14/14` in `RetPulse/tests/run_tests.lua`).
- Every new combat/unit/aura/chat read has an `issecretvalue` guard and `pcall` where client behaviour can vary.
- For in-game checks, instruct the user to run `/console scriptErrors 1` and `/reload` (and `/rp debug` for `RetPulse`, checking `RetPulseDB.lastError`). Use `/api search <Name>` in-game as the final source of truth for any unverified 16001 API.
