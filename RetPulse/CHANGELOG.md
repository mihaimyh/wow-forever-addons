# Changelog

All notable changes to **RetPulse** for **World of Warcraft: Forever (Interface 16001)** are documented in this file.

## [2.0.0] - 2026-11-24

### Added
- **PvP Intelligence Suite** (new `PvP` Settings subcategory, strictly isolated from PvE via enemy player / Battleground detection and gated by known spells for low-level compatibility):
  - **Auto-PvP Seal of Command & Burst**: automatically favors burst `Seal of Command` and offensive cooldowns against enemy players and inside Battlegrounds.
  - **Stun Combo (`STUN COMBO!`)**: prioritizes `Hammer of Justice` into `Judgement of Command` when the target is stunned or ready for a burst window.
  - **CC Breaker (`BREAK CC!`) & Mobility (`FREEDOM!`)**: detects loss-of-control and roots/snares (`C_LossOfControl`) to prompt `Will of the Forsaken` or `Blessing of Freedom` when needed.
  - **Repentance (`GAP CLOSE` / 2nd `INTERRUPT`)**: prompts `Repentance` at range to close the gap or as a backup interrupt against enemy healers/casters.
  - **Anti-Runner (`STOP RUNNER`)**: suggests `Seal of Justice` against fleeing or high-mobility enemy players.

## [1.9.0] - 2026-11-24

### Added
- **Nameplate Swing Bar & Echo Pips** (`nameplateBars`): compact swing timer bar and 3 Unsealed Wrath Echo pips attached directly below the Nameplate Mode icons.
- **Early Buff Refresh & Greater Blessings** (`buffRefreshEarly`, `preferGreaterBlessings`): refreshes Blessings with `< 60s` remaining out of combat and prefers `Greater Blessings` in raids.
- **Alert Sounds** (`alertSounds`): optional rising-edge `SOUNDKIT` audio cues for critical prompts (interrupts, facing alerts, CC/burst alerts).
- **Out-of-Combat Dispel Advisor** (`remindDispel`): suggests `Purify` / `Cleanse` on party/raid members or target with click-to-cast support.
- **Righteous Fury Anti-Aggro Warning** (`warnRighteousFury`): warns non-tank Paladins in groups when `Righteous Fury` is active.
- **Boss Burst Prompt** (`suggestBurst`): suggests `Avenging Wrath`, offensive racials, and on-use trinkets during boss encounters.

## [1.8.0] - 2026-11-24

### Added
- **Facing Target Alert**: displays `FACE TARGET` on the HUD and `FACE!` on the nameplate widget when `UI_ERROR_MESSAGE` reports you are not facing your target; automatically clears on melee swing, spell cast, target switch, or after 2 seconds.

## [1.7.5] - 2026-11-24

### Added
- **Nameplate Y Offset Slider**: `-40` to `+40 px` vertical positioning offset in Settings.

## [1.7.4] - 2026-11-24

### Added
- **Nameplate X Offset Slider**: `-40` to `+40 px` horizontal positioning offset in Settings.

## [1.7.3] - 2026-11-24

### Fixed
- **Nameplate Anchoring**: anchored nameplate rotation icons directly to `UnitFrame.healthBar` with a `-4 px` horizontal offset for tighter alignment across nameplate scales.

## [1.7.2] - 2026-11-24

### Added
- **Friendly Target Blessing Advisor**: suggests and click-to-casts the optimal Blessing on friendly non-party player targets (skipping other Paladins' active buffs).

## [1.7.1] - 2026-11-24

### Added
- **Masque Skinning Support**: optional integration registering `RetPulse` → `Nameplate Icons` and `HUD Icons` button groups.

## [1.7.0] - 2026-11-24

### Added
- **Nameplate Mode (`Attach to target nameplate`)**: compact `34x34` Main + `22x22` NEXT icons beside the selected enemy's nameplate, automatically falling back to the classic HUD out of combat or when no nameplate is visible.

## [1.6.2] - 2026-11-24

### Fixed
- Restored `ns:OpenOptions()` so `/rp config` and the Addon Compartment reliably open the Settings panel.

## [1.6.1] - 2026-11-24

### Changed
- Reorganized Settings into native subcategories (`RetPulse`, `Rotation & Mana`, `Buffs & Talents`, `Debug`) with clean section headers.

## [1.6.0] - 2026-11-24

### Added
- **Dungeon Mana-Saving Controls**:
  - Configurable **Auto-AoE enemy threshold** (`2+`, `3+`, or `4+` nearby enemies).
  - **Boss-only Crusader opener** option to save mana on trash packs.
  - **Low-Mana combat guard** using `insufficientPower` detection on `Consecration`.

## [1.5.2] - 2026-11-23

### Fixed
- Replaced icon pop `Frame:SetScale()` animation with `SetTexCoord` zoom to eliminate combat taint.

## [1.5.1] - 2026-11-22

### Fixed
- Parented the click-to-cast secure button to `UIParent` so HUD scale animations never trigger combat taint.

## [1.5.0] - 2026-11-22

### Added
- **Party & Raid Blessing Advisor**: scans group members for missing Blessings using class/power-type priority (`Kings` / `Might` / `Wisdom`), skips other Paladins' Blessings, and supports direct click-to-cast targeting.

## [1.4.5] - 2026-11-22

### Fixed
- Preserved true base weapon speed while `Seal of the Crusader` (+40% swing speed) is active.
- Limited the `Seal of the Crusader` boss/elite opener prompt to once per pull rather than re-prompting on every tab-target.

## [1.4.4] - 2026-11-22

### Fixed
- Fixed Auto-AoE melee enemy counting on WoW: Forever (16001) using `plate.unitToken`, `NAME_PLATE_UNIT_ADDED`/`REMOVED`, and `CheckInteractDistance` fallback.

## [1.4.3] - 2026-11-22

### Changed
- Redesigned the HUD into the Forever-safe **Command Plate** dark-glass layout with unified design tokens (`UITheme.lua`).

## [1.3.6] - 2026-11-22

### Fixed
- Restored Talent Advisor badges behind `PlayerSpellsFrame`.

## [1.3.5] - 2026-11-22

### Changed
- Internal code cleanup: shared spell/build/position helpers and unified `PriorityQueue:IsTwistReady()`.

## [1.3.4] - 2026-11-22

### Fixed
- Click-to-cast now works even while the HUD is unlocked and supports `ActionButtonUseKeyDown` (`LeftButtonDown` + `LeftButtonUp`).

## [1.3.3] - 2026-11-22

### Added
- **Out-of-Combat Click-to-Cast**: click the HUD icon out of combat (`SecureActionButtonTemplate`) to cast the recommended Seal, Blessing, or Aura directly.

## [1.3.2] - 2026-11-22

### Fixed
- Fixed 3+1 Unsealed Wrath detonation echo counting and rapid-swing `ConfirmSwing` handling.
- Prevented false 1.5s GCD lockouts on off-GCD casts and ensured learned cooldowns use `math.min`.
- Added secret-value (`ns.IsSecret`) and `IsForbidden()` safety guards across frame and interrupt checks (`notInterruptible`).
- Cleared cached seal state properly when buffs are cancelled, fixed Settings `Defaults`, and respected the `effects = false` FX toggle.

## [1.3.1] - 2026-11-22

### Fixed
- Stripped melee haste (`GetMeleeHaste()`) when computing base weapon speed so haste buffs (such as Warchief's Blessing) do not downgrade slow 2H weapons into fast-weapon seal logic.

## [1.3.0] - 2026-11-22

### Added
- **Initial CurseForge Release** for WoW: Forever (Interface 16001):
  - Unsealed Wrath echo tracker and weapon-speed Seal pairing engine.
  - Retribution priority queue with Auto-AoE, `Hammer of Justice` interrupt alerts, and Boss/Elite Crusader opener.
  - Secret-safe mana bar, swing timer bar, and animated FX feedback.
  - Interactive **Talent Advisor** (`RP NEXT` / `RP X/Y` / `RP ✓`) on the talent tree.
  - Out-of-combat Blessing & Aura reminders with persisted learned cooldowns.
