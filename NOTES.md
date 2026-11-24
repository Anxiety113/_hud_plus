# HUD Plus -- engineering notes

## Version tested / ground truth

- **Engine:** Godot `3.5.1.stable.custom_build.6fed1ffa3` (reported by the
  installed `YourOnlyMoveIsHUSTLE.exe --version`).
- **Game data:** installed build PCK, format v1, 5452 files. Scripts in the PCK
  are compiled `.gdc`; class reference pages on readthedocs were used for
  declarations, and the reference AI mod was used for live patterns.
- **Installed game used for API confirmation:**
  `C:\Program Files (x86)\Steam\steamapps\common\YourOnlyMoveIsHUSTLE`.
- **Reference implementations studied:** `datheia/yomintelligence`
  (`ModMain.gd`, `game.gd`, `AIController.gd`, `ModOptions.gd`, `_metadata`),
  yomi-docs class references for `Fighter`, `StateMachine`, `CharacterState`,
  `Hitbox`, `HurtboxState`.

---

## Assumptions (and why)

1. **`Fighter.any_available_actions` is not a move list.** In this build it is a
   `bool` (default `true`), as shown by the authoritative class reference. The
   working brief's description of it as "the legal move set" does not match the
   installed build. Legal candidates are therefore read from the live
   `action_cancels` dictionary (exactly how the reference AI enumerates UI moves),
   with a fallback scan of `state_machine.states_map` for `selectable` states.
   This remains zero-configuration for modded characters.
2. **`copy_to` direction is source → target.** Confirmed empirically in the
   reference implementation: `game.copy_to(ghost_game)` and
   `copy_from.chara.copy_to(copy_target.chara)`. HUD Plus only ever calls
   `live_game.copy_to(ghost_game)`.
3. **Whole-game cloning is the only safe way to advance ticks.** `Fighter.tick()`
   alone lacks the game context (objects, `objs_map`, stage, turn flags). HUD Plus
   instantiates a hidden `res://Game.tscn`, calls `start_game(true, match_data)`,
   copies live → ghost, resets ghost runtime flags, and advances with
   `ghost.simulate_one_tick()` — the same call and ordering the reference uses.
4. **RNG is mirrored by the whole-game copy.** This build carries
   `logic_rng`, `logic_rng_static`, `logic_rng_seed` and `logic_rng_static_seed`
   on fighters/objects. `Game.copy_to` copies these; HUD Plus does not attempt a
   partial manual seed copy, which would be easier to get wrong. The reference
   implementation's fast-copy path explicitly mirrors both RNG `seed` and
   `state`, confirming these are the fields that matter.
5. **Damage is normalized to 100-HP units before applying `dealt` / `taken`.**
   The brief's formula (`1.0 * dealt`) with raw 1500-HP damage would make the
   `kill` weight of 8 irrelevant. Normalizing keeps all exposed weights usable
   on the same scale. `kill` remains a flat +8 term as specified.
6. **Version gate uses engine version plus API presence.** The build exposes no
   reliable `application/config/version` value headless (Godot logs a warning),
   so `guard.gd` checks engine `3.5.1` and the presence of `copy_to`,
   `simulate_one_tick`, and `get_player` on the live Game. Any failure forces
   static-only mode rather than guessing.
7. **Divergence uses `get_state_hash()` before actions are queued** on the ghost,
   so queueing itself cannot be mistaken for a clone mismatch. Three mismatches
   mark the character static-only; three real clone failures engage the session
   kill switch. Both are logged, neither throws.
8. **DI is amortized.** The five directional micro-rollouts run one per frame in
   the same `step()` pipeline as candidate scoring, so they do not create a
   5x hitch when results are published.
9. **Reasons are derived from measured components only.** A reason such as
   "beats 6F startup" requires both startup values to be known and compared;
   "safe, +N on block" requires a measured plus frame and an in-range hitbox.
   If nothing is measurable the reason is "no clear advantage".
10. **Mod Options is soft-depended.** `mod_options.gd` is only installed as a
    script extension when `res://SoupModOptions/ModOptions.gd` exists. All values
    also live in a plain `ConfigFile`, so defaults work with the library absent.

---

## Dead ends

- The installed PCK stores scripts as compiled `.gdc`, so direct source
  decompilation was not attempted. String mining confirmed `simulate_one_tick`
  and `spectating` in `game.gdc`; the rest was cross-checked against the class
  reference and the reference mod.
- The Steam guide referenced in the brief (`id=3577160476`) is the "General AI"
  item, not a legal-move-enumeration guide, and is no longer publicly visible.
  The reference repository was used instead.
- The SoupModOptions library is not installed locally. Its menu-builder API
  (`generate_menu`, `add_label`, `add_number_slider`, `add_number_spinbox`,
  `add_bool`, `add_menu`) was taken verbatim from the reference mod. The polling
  bridge that mirrors values into our `ConfigFile` is deliberately defensive:
  it reads whichever of `value` / `text` the control exposes and otherwise
  leaves the defaults intact.
- A Godot pack parser had to account for **64-bit** `offset`/`size` fields in PCK
  v1 (Godot 3.5); an initial 32-bit parser desynchronized after two entries.

---

## Verification (section 10)

### V1 -- Parse check

Real Godot 3.5.1 binary, `--headless --script <file> --check-only`, run against a
project containing the mod. Result: **0 failures** for all 11 `.gd` files.
`game_extension.gd` was checked against a local stub base class because the
harness binary mounts its own embedded `game.gdc` ahead of the test project's
stub; with that substitution its own syntax is clean (exit 0).

### V2 -- Static analysis

All game-facing names used by the mod were checked against the authoritative
class reference and/or the reference implementation: `copy_to`,
`simulate_one_tick`, `get_player`, `current_state`, `action_cancels`,
`state_machine.states_map`, `queued_action`, `queued_data`, `queued_extra`,
`current_di`, `minus_frames`, `get_pos`, `get_state_hash`, `hp`, `MAX_HEALTH`,
`super_meter`, `burst_meter`, `air_movements_left`, `feints`, `sadness_enabled`,
`combo_proration`, `combo_damage`, `logic_rng*`, `start_tick`, `active_ticks`,
`damage`, `plus_frames`, `start_game`, `should_game_end`, `ReplayManager.playback`,
`Network.player_id`. No unresolved symbols were found in parse-checked code.
`any_available_actions` is intentionally not used as a move source (assumption 1).

### V3 -- selftest.gd output (pasted verbatim)

```
=========================================
HUD Plus selftest -- Godot 3.5.1-stable (custom_build)
=========================================
  PASS  sampler: at least three candidates (got 4)
  PASS  sampler: sample is valid
  PASS  sampler: distance computed
--- STATIC ---
  PASS  STATIC: result is valid
  PASS  STATIC: at least three ranked rows (got 4)
  PASS  STATIC: finite score for Super
  PASS  STATIC: reason for Super
  PASS  STATIC: finite score for Punch
  PASS  STATIC: reason for Punch
  PASS  STATIC: finite score for Armor
  PASS  STATIC: reason for Armor
  PASS  STATIC: finite score for Jab
  PASS  STATIC: reason for Jab
  confidence=55  di=no DI
   Super  100  kills, spends resource
   Punch  25  whiffs at this range
   Armor  21  whiffs at this range
   Jab  20  whiffs at this range
--- SIMULATED ---
  PASS  SIMULATED: result is valid
  PASS  SIMULATED: at least three ranked rows (got 4)
  PASS  SIMULATED: finite score for Super
  PASS  SIMULATED: reason for Super
  PASS  SIMULATED: finite score for Punch
  PASS  SIMULATED: reason for Punch
  PASS  SIMULATED: finite score for Armor
  PASS  SIMULATED: reason for Armor
  PASS  SIMULATED: finite score for Jab
  PASS  SIMULATED: reason for Jab
  confidence=80  di=no DI
   Super  100  kills, +2 frame advantage, spends resource
   Punch  33  hits for 700, +2 frame advantage
   Armor  24  hits for 500, +2 frame advantage
   Jab  20  hits for 400, +2 frame advantage
SELFTEST RESULT: PASS
```

(Exit code 0. The synthetic Game double deliberately applies the queued move's
damage regardless of range, which is why simulated reasons do not repeat the
static "whiffs at this range" line; the reasons still describe the numbers the
scorer actually computed.)

### V4 -- Headless load of the mod

The installed game binary was used for parse checks and for the selftest,
**but a full in-game headless registration run was not performed**: the build
requires a valid Steam app id / initialized Steam client before it will create a
match, and the headless environment reports `Invalid app ID or app not
installed`. A temporary copy was placed in the real `mods/_hud_plus` folder and
the game was launched with `--headless --quit`; it exited before the mod loader
emitted any log lines, so no registration was observed, and the test copy was
removed afterwards. Registration is therefore verified by inspection of `ModMain.gd`
against the reference implementation's `_init(modLoader)` /
`installScriptExtension` pattern, not by an observed in-game load.

### V5 -- Live-state write inspection

Inspected every call site:

- `sampler.gd` -- only `get()`, `get_property_list()`, `callv("current_state")`,
  `callv("get_pos")`, and `has_method()`. No setters, no `tick`, no `update_data`.
- `scorer.gd` -- every `set()` target is the ghost Game, a ghost fighter, or the
  injected synthetic test double. `game.copy_to(ghost)` copies live → ghost.
  `simulate_one_tick()` is called only on the ghost. `update_data()` is never
  called in the shipped path.
- `renderer.gd` / `hud_controller.gd` -- read-only; the controller only adds its
  own child node and writes to its own config file.
- `game_extension.gd` -- only calls `._ready()` and `add_child()` for our node.

No code path writes to a live Fighter.

### V6 -- Mod Options absent

`ModMain.gd` guards the optional extension with
`ResourceLoader.exists("res://SoupModOptions/ModOptions.gd")`. The local install
has no SoupModOptions folder. Selftest ran with the library absent and passed.
All settings come from `scoring_config.gd` hardcoded defaults plus
`user://hud_plus_config.cfg`, so the mod is fully functional without it.

---

## Known limitations

- A **full ten-turn live match (A6) was not executed** in this environment; no
  Steam-backed match could be started headless. Crash resistance is provided by
  guarded reads, validity checks, the static fallback, and the kill switch, but
  it has not been observed across a real online match.
- **Three modded characters were not available locally** (the `mods` folder
  contained only `workshop_upload`). Modded-character support is designed to be
  configuration-free via `action_cancels` / `states_map`, and the divergence
  detector flags characters whose clone misses custom state, but the requested
  three-character test could not be run.
- The static fallback can only see metadata exposed by a state's hitboxes
  (`start_tick`, geometry, `damage`, `plus_frames`). Characters that compute
  frame data entirely in custom scripts without exposed hitboxes will be marked
  `unknown frame data` and ranked conservatively.
- Reasons are capped at three components per row to fit the small HUD.
- The ghost Game is created lazily on the first scoring pass; the first match
  with a given character may take slightly longer to set up. Subsequent passes
  reuse the pooled ghost.
- `mod_options.gd` mirrors values into our config by polling exposed control
  properties. If a future SoupModOptions version hides those properties, the
  panel still displays every setting and the config file remains authoritative.
- HUD Plus ranks the moves the live UI exposes; it does not enumerate multi-tick
  plans or combo routes, and it does not model opponent mixups beyond the
  opponent's currently committed action and DI.
