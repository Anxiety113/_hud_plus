# HUD Plus

A small, clientside combat-advisor overlay for **Your Only Move is HUSTLE**.

HUD Plus watches the live match and ranks the moves you can currently select. It
**only gives advice**. It never presses a button, never locks in a move, never
sets your DI for you, and never writes to a live Fighter. It works in online PvP;
your opponent does not need the mod.

---

## Install

1. Find your game's mods folder:
   - Steam: `C:\Program Files (x86)\Steam\steamapps\common\YourOnlyMoveIsHUSTLE\mods`
   - Linux: `~/.local/share/Steam/steamapps/common/YourOnlyMoveIsHUSTLE/mods`
2. Copy the whole folder named **`_hud_plus`** into that `mods` folder. The final
   path must be `mods/_hud_plus/ModMain.gd`.
3. Enable mods in the game's settings and restart the game.
4. Start a match. The overlay appears in the top-left.

Nothing else is required. **Mod Options Menu** ("SoupModOptions") is optional:
if it is installed, HUD Plus adds a settings page; if not, the built-in defaults
are used and the mod runs normally.

---

## What you see

Three rows, best first:

```
HUD Plus
1  Super                    ████████  100  kills, spends resource
2  Punch                    ██         33  hits for 700, +2 frame advantage
3  Jab                      ██         20  hits for 400
confidence 80%  |  simulation active  |  no DI
```

- **Rank / move name / score bar / reason.** Green = strong, amber = middling,
  red = weak.
- **Reason** is generated only from values that were actually measured (damage
  dealt, damage taken, kill, whiff, block, parry, armor, invulnerability, frame
  advantage, startup comparison, resource cost). It is never generic filler.
- **Confidence** is derived from the gap between first and second place. A close
  race shows `close call -- low confidence`.
- **DI line** appears when the best line still takes a hit. It names the DI
  direction that took the least damage in extra rollouts, or `no DI` when no
  direction helps. This is advice only — you still choose your own DI.
- **`STATIC`** on a row, or `static-only` in the footer, means simulation was
  unavailable and the static fallback ranked that row. Static scores are
  deliberately given lower confidence.

The overlay hides automatically during character select, menus, replays,
spectating, and while a game is not active.

---

## Hotkeys

| Key | Action |
| --- | --- |
| **F7** | Show / hide the overlay |
| **F8** | Cycle verbosity: full (3 rows) → top only (1 row) → off |
| **F6** | Hold and move the mouse to drag the panel |
| **F9** | Hold and move the mouse up/down to scale the panel |

F7/F8/F9/F6 can be rebound by editing `user://hud_plus_config.cfg` (see below).
Godot key scancodes are used: F6 = `16777249`, F7 = `16777250`,
F8 = `16777251`, F9 = `16777252`.

---

## Settings

Settings live in `user://hud_plus_config.cfg`. You can edit it by hand while the
game is closed, or use the optional Mod Options page (**HUD Plus** on the title
screen). The file is created the first time a hotkey or option changes a value.

### Scoring weights (`[weights]`)

| Key | Default | Meaning |
| --- | --- | --- |
| `dealt` | `1.0` | Damage dealt. Damage is converted to 100-HP units before weighting. |
| `kill` | `8.0` | Bonus when the rollout kills the opponent. |
| `frame_advantage` | `0.35` | Ending frame advantage (positive is plus). |
| `corner_carry` | `0.4` | Distance pushed toward the corner. |
| `taken` | `1.0` | Damage taken (subtracted). |
| `whiff` | `2.5` | Penalty when an attack deals no damage. |
| `resource` | `0.6` | Penalty for super / air-movement cost. |
| `armor_invuln` | `1.2` | Bonus when armor or invulnerability is used. |
| `risk_aversion` | `1.0` | Master slider. Scales **only** `taken` and `whiff`. Set to 0 to ignore danger, higher to play safer. |

`0.0` disables any term. Negative values are accepted but are not recommended.

### Simulation / pacing (`[sim]`)

| Key | Default | Range | Meaning |
| --- | --- | --- | --- |
| `tick_depth` | `24` | 6–60 | Ticks advanced per candidate rollout. |
| `min_tick_depth` | `6` | — | Floor used when auto-shrinking. |
| `max_tick_depth` | `60` | — | Ceiling for `tick_depth`. |
| `candidate_cap` | `8` | 3–8 | Maximum distinct moves ranked per turn. |
| `rate_hz` | `16` | 6–20 | Target scoring passes per second. |
| `frame_budget_ms` | `4.0` | 1–4 | Hard main-thread budget per frame. |
| `wall_budget_ms` | `250.0` | — | If a full pass exceeds this, tick depth is reduced once and logged. |

### UI (`[ui]`)

| Key | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | Master visibility (F7). |
| `verbosity` | `0` | 0 = full, 1 = top only, 2 = off (F8). |
| `toggle_key` | `16777250` | F7 scancode. |
| `verbosity_key` | `16777251` | F8 scancode. |
| `drag_key` | `16777249` | F6 scancode. |
| `scale_key` | `16777252` | F9 scancode. |
| `offset_x`, `offset_y` | `14`, `14` | Panel position, updated when dragging. |
| `scale` | `1.0` | Panel scale, 0.7–1.8. |
| `show_confidence` | `true` | Show confidence and status in the footer. |

---

## How it stays safe

- **Read-only.** All reads go through guarded getters that check validity and
  the object's real property list. No live Fighter is ever called with a
  mutating method.
- **Throwaway clones.** Simulation runs on a hidden, invisible ghost `Game`
  created from the game's own `Game.tscn`. Game state is copied *into* the ghost;
  the live game is never copied into.
- **Version gate.** HUD Plus records the engine version at load. On a mismatch,
  or if required simulation methods are missing, it forces static-only mode.
- **Clone checks.** After each copy, a cheap state checksum is compared. Three
  divergences mark that character static-only for the session. Three genuine
  clone failures engage a global kill switch and keep static mode for the
  session. Nothing crashes.
- **Frame budget.** One candidate rollout per frame, a 4 ms cap, and an 8
  candidate / 60 tick hard cap. If a pass takes too long, the tick depth is cut.
- **No per-character data.** Candidate moves come from the live
  `action_cancels` map and, as a fallback, the live state machine. No character,
  stance, or move names are hardcoded.

---

## Troubleshooting

**Nothing shows up.** Confirm the folder is `mods/_hud_plus` (not nested another
level), mods are enabled, and you are in an actual match. Press F7. Check the
`godot.log` for `[HUD Plus] loaded`.

**Every row says `static`.** Simulation was unavailable: wrong engine version,
missing game API, clone failures, or the character was flagged as diverging.
Static mode is intentionally useful — it ranks by startup, reach vs distance,
damage, armor/invulnerability and cost — but it cannot predict outcomes. Try a
different character to see whether the flag is character-specific.

**It feels slow.** Lower `tick_depth`, lower `candidate_cap`, or lower `rate_hz`.
The log will say `[HUD Plus] reducing search depth ...` if the 250 ms wall
budget was hit.

**A modded character gives odd advice.** That character's custom logic likely
mutates state that a generic clone cannot capture; HUD Plus should flag it
static-only after repeated divergence. No configuration is needed.

**Confidence is low.** The top two moves scored nearly the same. Treat the
advice as a tie, not a verdict.

---

## Selftest (V3)

Place the folder at the root of a Godot 3.5 project and run:

```
godot --headless --path <project> --script res://_hud_plus/selftest.gd
```

It builds a synthetic two-fighter match, runs a complete static pass and a
complete simulated pass, and asserts non-empty ranked output with finite scores
and truthful reasons. Expected final line: `SELFTEST RESULT: PASS`.

---

**Version tested:** Godot 3.5.1.stable.custom_build.6fed1ffa3 (PCK v1).
See `NOTES.md` for exact verification results and known limitations.
