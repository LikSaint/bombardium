# Bombardium

Top-down party bomber prototype, 1-4 players local co-op/versus. See project brief for full design.

## Requirements

Godot 4.7 (confirmed via `godot --headless --quit` in this environment — every scene parses and
loads with no script errors; behavior/feel itself still needs an interactive playtest in the editor).
Pixel-art assets (`assets/characters/`, `assets/icons/`, `assets/props/`) are AI-generated via the
PixelLab MCP server, not hand-drawn — see "Art pipeline" below for regenerating/extending them.

## Running

Open the project in Godot 4 and press F5. Launches maximized, using the whole screen. It boots into
the **Lobby** (`scenes/Lobby.tscn`) — join/ready/character state is still icon/symbol-driven (a "+"
slot, the ready checkmark, blinking cycle arrows), but every screen now also spells out its hotkeys
and other state as plain text, since icons alone weren't discoverable enough:

- **Join / ready**: Space (keyboard) or A (gamepad) — a "+" slot becomes your character portrait;
  press again to toggle ready, which also prints "ГОТОВ" on the slot (not just the checkmark).
- **Cycle character**: A/D (keyboard) or D-pad left/right (gamepad), only while not ready. Each
  joined slot shows a one-line blurb of that character's passive/ability underneath the portrait.
- **Map size**: keyboard only, Up/Down — 5 bar-height presets, Крошечная (9x7) to Огромная (21x17).
- **Add/remove bot**: keyboard only, B fills the next open slot with an AI-controlled bot (a random
  character, instantly ready — shown with an "ИИ" badge instead of the ready checkmark); N removes
  the most recently added bot. Bots play with the same character/rules as anyone else, just slower
  to react than a human would be (see Architecture notes).
- A hotkey legend for all of the above sits fixed at the bottom of the Lobby screen.
- Match starts automatically once at least one device has joined and everyone is ready. Starting
  solo (exactly 1 slot, no one else) auto-fills a bot into the 2nd slot — a lone player can never
  become "the last survivor" on their own, so without this the round would just never end.

In-match:
- Move: WASD or left stick — a proper 4-direction walk cycle (6 frames/direction), paced to each
  character's actual move speed; standing still shows the idle sprite for whichever way you're facing.
- Bomb: Space / A. Ability: E / B. Pickup (stub, not yet implemented — intentionally left off every
  hotkey legend below): Q / X.
- A hotkey hint (movement/bomb/ability/pause) shows at the top of the screen for the first 6s of
  each round, then fades out — it reappears every round since `Main` reloads the scene each time.
- **Escape (keyboard) or Start (gamepad) opens the pause menu** — Resume / Restart match / Back to
  lobby / Quit, icons only, plus a small hotkey hint for navigate/select/close. Only the device that
  opened it can navigate or close it (shown by name + portrait in the menu title), so nobody else
  can hijack or dismiss someone else's pause.
- If your controller disconnects mid-match, your character just stops responding, and a red
  "ОТКЛЮЧЕН" badge appears over their HUD corner portrait so it's clear what happened instead of
  looking like a freeze. Any controller (not necessarily the same physical one) pressing its join
  button (Space/A) reclaims control — most-recently-dropped player first — starting next round.
- On death, a character picker (portrait + left/right arrows, plus a hotkey hint that reads "A/D" or
  "◄►" depending on whether that player's on keyboard or gamepad) appears at the bottom of the
  screen for that player; change character while the round continues, effective next round. If that
  player's controller drops while the picker is up, it shows "Отключено…" and ignores input until a
  controller reclaims that player, then re-syncs to whichever device (possibly a different physical
  pad) picked it up.
- Each player's portrait (tinted to their team color) and upgrade-level icons (bomb count/radius/
  speed/shield) are always shown in a HUD corner matching their spawn corner.
- Disconnect/reconnect is also guarded outside of a live round: in the **Lobby**, a joined player's
  controller dropping instantly frees their slot (rather than leaving a phantom slot that can never
  ready up and blocks the match from starting) — reconnecting is just joining again. If the
  controller that opened the **pause menu** disconnects while it's open, the menu auto-resumes
  instead of soft-locking the game paused forever (since, by design, no other device is allowed to
  touch someone else's pause menu).
- Placed bombs pulse faster and glow redder the closer they are to going off.

## Status (MVP priority list)

- [x] 1. Grid movement + base bomb + destructible blocks
- [x] 2. Local multiplayer — Lobby join flow (up to 4, keyboard + gamepads), mid-match disconnect/reconnect handling
- [x] 3. Rounds/score UI — 5s results overlay between rounds, 5-round match, match winner by score
- [x] 4. Character roster + abilities — Bomb-Master, Scout, Engineer, Pyro, Bomb-Kicker (5 characters; brief listed 4, added a 5th per later request)
- [~] 5. Powerups — bomb count/radius/speed/shield drop from blocks and sit on the ground until collected (bobbing icon, never destroyed by blasts); extra weapon *pickups* (mine/remote/fire bomb) not yet built
- [~] 6. Art — AI-generated (PixelLab) pixel-art characters with walk animations, HUD/pickup icons, pause menu icons, blocks, walls, explosions, temp wall all done. No sound yet.

## Characters

| Character | Passive | Ability (B / cooldown ~2.5s) |
|---|---|---|
| Bomb-Master | +1 blast radius, +1 bomb, from the start | — |
| Scout | +20% move speed | Dash 2 cells in facing direction |
| Engineer | — | Place a temp wall (5s) on your own cell, destroyed early by a blast |
| Pyro | — | Every bomb explodes in a radius, not a cross |
| Bomb-Kicker | — | Kick the bomb in front of you; it slides until it hits an obstacle, and can still explode mid-slide |

Bombs chain-detonate: any blast that reaches another bomb sets it off immediately too.

## Art pipeline

Characters, icons, and props are generated through the **PixelLab MCP server** (`mcp__pixellab__*`
tools), not hand-drawn. Each of the 5 characters is a single flat-shaded sprite per direction —
`assets/characters/<name>_south.png` / `_north.png` / `_east.png` / `_west.png` (idle) plus
`assets/characters/walk/<name>_<direction>_<0-5>.png` (6-frame walk cycle per direction, from
PixelLab's `walk` template animation). `scripts/Constants.gd`'s `CHARACTER_SPRITES` /
`CHARACTER_WALK_FRAMES` map character × direction (× frame) to the preloaded textures.

Team color is a **soft whole-sprite tint**, not a clothes-only layer: PixelLab characters come back
as one flat image (not separable body/clothing layers), so `CharacterPortrait.gd` blends each
player's `Consts.PLAYER_COLORS` onto the sprite's `modulate` at `TEAM_TINT_STRENGTH` (0.4) — full
strength washes out skin tone, so this is a deliberate compromise, not a bug.

`scenes/CharacterPortrait.tscn` + `scripts/CharacterPortrait.gd` is the one reusable widget
(`set_character()`, `face(dir)`, `set_walking()`) instanced by the in-game `Player`,
`PlayerHudCorner`, the post-death `CharacterDockSlot`, `LobbySlot`, and `PauseMenu`'s title — so
swapping in better character art only has to happen in one place (`Consts.gd`'s texture arrays).

`assets/icons/*.png` (bomb/radius/speed/shield stat icons, the pause menu's resume/restart/lobby/quit
icons, and the in-arena `bomb_round.png`) and `assets/props/*.png` (block, wall, explosion, temp
wall) are flat single-layer PNGs, no tinting. Icons came back at inconsistent native pixel sizes
from PixelLab (e.g. 84x92 vs 100x95) — anything displayed via a raw `Sprite2D` (the ground-lying
`Powerup`) normalizes against that at runtime (`Powerup.gd`'s `TARGET_SIZE`); anything in a `Control`
(`TextureRect` with `stretch_mode = 5`, in the HUD/pause menu) already auto-fits regardless.

One exception: the in-arena placed-bomb sprite (`Consts.BOMB_TEXTURE`) is **not** the PixelLab bomb
— it's still a tiny hand-drawn Pillow circle, because the fuse-shortening animation
(`scripts/Bomb.gd`) draws its own `Line2D` fuse + spark on top and needs a bomb body with no fuse
already baked in. PixelLab's `edit_image` (asked to strip the fuse off its generated bomb) was tried
once, cost ~20 generations, and failed on a content-policy check — not worth retrying. The PixelLab
bomb (with its own baked fuse) is used as-is for the static `assets/icons/bomb.png` HUD stat icon,
where nothing needs to animate.

Regenerating art means re-running the PixelLab MCP calls (`create_character`, `animate_character`
with `template_animation_id="walk"`, `create_image_pixen`, `edit_image`) — there's no local script,
and the trial account has a hard cap on generations (`get_balance`), so budget before batching a lot
of characters/animations at once. `animate_character` in template mode queues one job per direction
(4 here) and the API caps you at 8 concurrent jobs, so animating 2+ characters at once needs to be
staggered. After adding/changing any PNG, Godot needs to (re)import it before a headless run can
preload it — either open the project in the editor once, or run
`godot --headless --editor --path . --quit`.

## Architecture notes

- Grid size is a runtime setting now (`Consts.set_map_size`), chosen in the Lobby — not a fixed
  const. `Consts.CELL_SIZE` (64px) stays fixed; `Main._fit_camera_to_arena()` zooms the camera to
  fit whichever map size was picked inside the current window/viewport size.
- Window opens maximized (`window/size/mode=2`) with stretch aspect `expand`, so the game fills
  whatever screen it's on rather than a fixed small box; `default_texture_filter=0` (Nearest) keeps
  the pixel art crisp at any scale.
- All blocking/collision (walls, blocks, bombs, temp walls) is resolved logically via `Arena`
  dictionaries, not physics — movement is grid-cell-to-grid-cell via Tween. Powerups are the one
  thing that doesn't block movement, only trigger pickup on arrival.
- Gamepad input is read directly by device index (`Input.get_joy_axis`/joypad button events) in
  `scripts/Player.gd`, not through the InputMap — this is what makes per-player device binding,
  live reassignment (post-death picker), and reconnect-reclaiming possible without editor-side
  input config. `PauseMenu` uses the same pattern to lock itself to whichever device opened it.
- `GameManager.player_slots` (set once by the Lobby) is the single source of truth for who's
  playing which character on which device; it survives round-reloads (`reload_current_scene`)
  within a match, so mid-round changes (character reselect, controller reclaim) simply take effect
  the next time `Main._spawn_players()` reads it. `GameManager.leave_to_lobby()` (from the pause
  menu) clears it back to empty.
- `Consts` and `GameManager` are autoloaded singletons (see `[autoload]` in `project.godot`).
- Bots are a `player_slots` entry with `device = Consts.DEVICE_BOT`, added from the Lobby (B key) —
  no separate bot scene/node type. In `Player.gd`, `is_bot` (set from `device_id` in `_ready`)
  swaps `_poll_move_dir()`/`_input()` for `_bot_think()`, run on a `BOT_DECISION_INTERVAL` timer
  (0.6s ± jitter, tuned down from an initial 0.2s that made bots feel too sharp/twitchy — a bot only
  attempts one grid step per decision and stands still in between, it doesn't keep running in the
  last-chosen direction for the whole interval): compute every live bomb's blast cells, flee via BFS
  if standing in one, otherwise BFS toward the nearest block/enemy and drop a bomb only if a safe
  post-blast escape path still exists (that escape check's BFS deliberately ignores blast-footprint
  cells while pathing through them — only the final resting cell has to be outside the blast, since
  the multi-second fuse gives time to walk clear). Bots don't use character abilities yet (passives
  like Bomb-Master/Scout still apply).
- `Lobby._maybe_start()` auto-appends one bot slot if the match would otherwise start with exactly 1
  player — `GameManager.player_died()` only fires `round_ended` once exactly one player remains
  *after someone else died*, so a true solo match could never end on its own.
- Export presets (Linux/Steam Deck primary, Windows secondary) aren't configured yet — set these
  up in-editor under Project > Export.

## Known simplifications / not yet done

- Pyro's circle blast doesn't respect line-of-sight occlusion (a block inside the radius doesn't
  shield cells behind it, unlike the cross blast).
- Reconnecting a controller only restores control starting the *next* round, not instantly.
- Mine / remote bomb / fire bomb weapon pickups from the brief aren't built.
- Team color tinting is whole-sprite (see Art pipeline) — not as clean as a clothes-only tint would
  be, but PixelLab doesn't hand back separable layers.
