# RetPulse — accepted specification (snapshot 2026-11-14)

This is the single source of truth the code is reviewed against. It merges the
original PRD with the decisions taken afterwards, and records the client
constraints discovered by probing the game.

## Target

- World of Warcraft: Forever (Classic+), Mainline client family, TOC `16001`,
  `WOW_PROJECT_ID == 18` (`WOW_PROJECT_CAMELOT`).
- Folder `Interface\AddOns\RetPulse`, SavedVariables `RetPulseDB`.
- No external libraries, CurseForge-ready, English UI strings only.

## Hard client constraints (measured, not assumed)

- No combat log: `COMBAT_LOG_EVENT_UNFILTERED` must not be used for anything.
- In combat: unit auras are inaccessible to tainted code (`Auras cannot be
  accessed when secret`), `UnitPower`, `UnitHealth` and `GetSpellCooldown` are
  secret values. `UnitCreatureType`, `IsSpellUsable`, `IsSpellInRange`,
  `PLAYER_SWING` are readable.
- Therefore: no mana gate, no target-health gate, no aura reading in combat,
  cooldowns timed locally from cast events, seals tracked from cast events.

## Functional requirements

1. **Swing timing** from `PLAYER_SWING` (main hand only), with duplicate events
   ignored while the current swing is still running. Reset on weapon change,
   on attack-speed change, and on leaving combat.
2. **Seal tracking**: active seal from cast events (rank-proof, 30 s expiry),
   aura scan only out of combat, any "Seal of …" aura counts.
3. **Unsealed Wrath echoes**: 3 max, 15 s. Source order: Blizzard Cooldown
   Manager → player aura → internal swing model. Swings that end in
   MISS/DODGE/PARRY/IMMUNE/DEFLECT/EVADE (from `UNIT_COMBAT`) must not add a
   stack. A main-hand weapon swap clears all stacks.
4. **Seal pairs by weapon speed** (default `video` mode): fast ≤2.5 →
   3× Righteousness then 1× Fury; medium 2.6–3.2 → 2× Righteousness then
   1× Command; slow ≥3.3 → 3× Command then 1× Righteousness. `icy` mode
   (2 thresholds at 3.0) remains selectable. Without the Seal of Command
   talent, the fast pairing always applies.
5. **Twist gating**: recommend the secondary seal only when a global (1.5 s)
   still finishes before the next white swing.
6. **Priority queue**: missing seal → twist at target stacks → Judgement →
   Holy Strike → Exorcism (Undead/Demon only) → Hammer of Wrath (open swing
   window only) → Consecration (AoE toggle) → back to the primary seal after
   the detonating swing.
7. **Safety**: Judgement must never be recommended while Seal of Fury is up
   (its Judgement is a taunt).
8. **GCD**: every non-Judgement cast spends a 1.5 s global; Judgement is
   off-GCD and never blocked by it.
9. **HUD**: compact panel, main icon with a circular swing ring, next-action
   icon, three diamond echo pips, echo decay bar, status line (`SWAP NOW`,
   `SEAL 2.4s`, countdown, `out of range`, `no target`), collapsed to a shorter
   panel when the echo tracker is inactive. Draggable when unlocked, position
   and scale persisted.
10. **Effects**: holy aura, ring, burst on SWAP NOW, sparks on echo gain,
    generated textures only, disabled outside combat, toggleable.
11. **Diagnostics**: `/retpulse debug` writes 16+ probe lines into
    `RetPulseDB.debugLog`; a per-pull combat log (`PULL`, `TARGET`, `SWING`,
    `SWINGRESULT`, `CAST`, `NEXT`, `WEAPON`, `END`) is appended to
    `RetPulseDB.combatLog`, capped, and flushed on `/reload`.
12. **Commands**: `config | lock | unlock | combat | trace on|off|clear|dump |
    auto | aoe | twist | uw | brackets | log [clear] | effects | sound |
    scale | reset | debug`.
13. **Options panel** via the Settings API, same keys as the slash commands.
14. **Flight recorder**: `/retpulse trace on` records decoded events plus a
    periodic snapshot of every module (visibility decision, seal, echoes,
    queue, gcd, weapon, effects) into `RetPulseDB.traceLog`; `/retpulse trace
    dump` writes a one-shot deep state into `RetPulseDB.dump`. Both are flushed
    by `/reload` so the maintainer can read them from disk.
15. **Visibility**: `combatOnly` (default on) shows the HUD only while in
    combat; unlocking reveals it for 60 seconds for placement.
16. **Deliberate extras** (approved later, not in the first PRD): addon
    compartment button, `/rp` alias, manual seal pair override, `/retpulse
    twist` for twisting below level 40, `/retpulse uw` manual talent override,
    cooldown learning from observed cast intervals, Two-bracket checkbox mirror.

## Out of scope

- Automation, macros, secure-frame keybinds, chat/party messages, damage meters.
- Anything that needs a secret value for a decision.
