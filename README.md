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
- **Cycle character**: A/D (keyboard) or D-pad / left stick left-right (gamepad), only while not ready. Each
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

Controller support (`scripts/PadInput.gd`, autoloaded as `Pad`) — the game reads joypads by device
index rather than through the InputMap, so that four local pads can be told apart, which means it
also has to absorb the differences between pad families itself:
- **Left stick doubles as the D-pad.** Menus, the Lobby and the character dock all navigate on
  `JOY_BUTTON_DPAD_*`; `Pad` watches each device's left stick and injects real D-pad press/release
  events for that device when it crosses a deadzone. Unbranded pads with no entry in Godot's SDL
  mapping database often report their D-pad as a raw hat that never becomes a `DPAD_*` event, and
  some pads have no D-pad worth using — either way the stick now gets them through every screen.
- **Button glyphs follow the pad.** Xbox/generic (A/B/X/Y), PlayStation (✕ ○ □), and Nintendo, which
  prints its face buttons mirrored: Godot's `JOY_BUTTON_*` names are positional, so on a Switch pad
  the bottom button that fires "A" actions is printed **B**, and the left one is **Y**. Only the
  glyphs change, never the bindings. Detected by USB vendor id, falling back to the controller name
  (`get_joy_info()` comes back empty on some platforms, notably macOS with the editor's embedded
  game window).
- **The primary button is learned, not assumed.** `JOY_BUTTON_A/B/X/Y` are *positional* names Godot
  derives from the pad's SDL mapping — on a correct one, `JOY_BUTTON_A` is the bottom button
  whatever the vendor printed there. Cheap PC pads break that in both directions: some carry no
  mapping and report raw firmware indices, others carry a mapping that is wrong for the hardware or
  sit in a DirectInput mode it was never written for, and their bottom button arrives as
  `JOY_BUTTON_B`. Hardcoding `JOY_BUTTON_A` then puts every primary action on a button nobody is
  pressing. So any face button confirms in menus, and whichever one a device first confirms with
  (title screen, Lobby join, reconnect claim) becomes that device's primary from then on; ability
  and pickup are placed at fixed offsets around the four-button cluster, wrapping so the three
  in-match actions can never collide. A standard pad is unaffected — its first confirm is A, which
  lands ability on X and pickup on B, exactly the old layout.
- **`scenes/PadDebug.tscn`** is a dev-only inspector for when a pad still misbehaves: run it
  directly (F6) and it shows each connected pad's name, GUID, `is_joy_known`, live held buttons and
  axes, and a log of raw button indices as you press them. Which physical button is `JOY_BUTTON_A`
  isn't answerable from code, so this is how you find out rather than guess — and what you'd need
  to write a proper `Input.add_joy_mapping()` entry for that GUID.

In-match:
- Move: WASD, or left stick / D-pad — a proper 4-direction walk cycle (6 frames/direction), paced to each
  character's actual move speed; standing still shows the idle sprite for whichever way you're facing.
- Bomb: Space / A. Ability: E / X. Pickup (stub, not yet implemented — intentionally left off every
  hotkey legend below): Q / B.
- A hotkey hint (movement/bomb/ability/pause) shows at the top of the screen for the first 6s of
  each round, then fades out — it reappears every round since `Main` reloads the scene each time.
- **Escape (keyboard) or Start (gamepad) opens the pause menu** — Resume / Restart match / Back to
  lobby / Quit, icons only, plus a small hotkey hint for navigate/select/close. Only the device that
  opened it can navigate or close it (shown by name + portrait in the menu title), so nobody else
  can hijack or dismiss someone else's pause.
- If your controller disconnects mid-match, your character just stops responding, and a red
  "ОТКЛЮЧЕН" badge appears over their HUD corner portrait so it's clear what happened instead of
  looking like a freeze. Any controller (not necessarily the same physical one) pressing its join
  button (Space/A) reclaims control — most-recently-dropped player first — and that character
  responds again immediately, mid-round. The reclaiming pad usually comes back under a *different*
  device index than it had before (SDL hands out a fresh one on re-plug), so the live character
  re-reads its index from the reconnect signal rather than trusting the one it spawned with.
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
- [~] 6. Art & audio — AI-generated (PixelLab) pixel-art characters with walk animations, HUD/pickup icons, pause menu icons, blocks, walls, explosions, temp wall all done. Procedural sound effects and two music loops are in; no voice/announcer.
- [x] 7. Sudden death — a round that drags past 5 minutes gets walled in from the outside

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

## Audio

Everything is synthesized offline into 16-bit PCM wavs — no licensed samples, no runtime synthesis.
Two autoloads, deliberately kept apart so they can be balanced against each other:

- `Sfx` (`scripts/Sfx.gd`) — short one-shots played through a round-robin pool of 8
  `AudioStreamPlayer`s, so overlapping events (two bombs going off together) don't cut each other
  off. `play(name, pitch, jitter)` adds a little random pitch spread by default, which keeps
  repeated footsteps from sounding mechanical.
- `Music` (`scripts/Music.gd`) — two looping themes, `Track.MENU` (calm, 96 BPM, 60s) for the main
  menu and lobby and `Track.ARENA` (bouncy platformer march, 144 BPM, 53s) for matches, crossfaded
  over 0.8s by `play_track()` so entering or leaving a match never cuts the audio mid-phrase.
  Repeat calls for the track already playing are ignored, so main menu -> lobby doesn't restart it.
  Runs with `PROCESS_MODE_ALWAYS` (pausing doesn't stop the music, and the crossfade tween still
  advances) and stops outright at volume 0 instead of playing silently.

Both tracks are note sequences — lead, bass, chords, and for the arena some light drums — written
straight into a buffer, so a loop is seamless as long as note tails are wrapped modulo the buffer
length; the tone shaping is done with FFT filters, which are circular and therefore also loop-safe.
Everything is deliberately dull-edged (nothing meaningful above ~4 kHz) because the music plays
under gameplay for a long time and shrill harmonics get tiring fast.

Menus use a **single** sound, `assets/sfx/menu.wav`, for every interaction — move, confirm, back,
join, ready — played at a fixed pitch with no jitter via `Sfx.play_menu()`. Distinct per-action
menu sounds were tried first and made simply moving through a menu feel noisy; the selection
highlight already says what happened, so the audio only needs to confirm that the input landed.

Both volumes are 0..1, adjusted in 5 steps from the Settings panel (main menu and pause menu share
the same three-row Language / Sound / Music layout) and persisted to `user://settings.cfg` next to
the language setting — each writer re-loads the file before saving so it never clobbers the others'
keys.

## Sudden death

A round that runs past 5 minutes starts closing in (`scripts/SuddenDeath.gd`, a node on `Main`).
Permanent walls drop one at a time, clockwise from the top centre of the arena and spiralling
inward, until the arena is sealed or someone is the last one standing.

- **Telegraphed, not instant.** Each wall puts a ghost sprite on its cell that fades up over exactly
  the current interval, then snaps to solid. The alpha curve is quadratic, so it lingers barely
  visible and only becomes obvious right before it lands — at the start you get seconds of warning,
  by the end it's a blink.
- **Accelerating.** The interval shrinks geometrically from 3s to 0.28s across the whole spiral,
  not linearly, so it opens gently and then rushes. Fully sealing a map takes ~34s (Tiny) to ~4min
  (Huge); in practice rounds end well before that.
- **Crushing.** A player standing where a wall lands takes a hit — a shield absorbs it exactly like
  a blast — and is shoved one cell along the direction the wall front is travelling. With no shield
  they die and simply vanish, like any other death. The shove happens even during post-shield
  invulnerability, because the alternative is a player standing inside solid stone; if no adjacent
  cell is free in any direction, the crush kills regardless of shields.
- **Music leans on the gas.** `Music.set_pitch()` ramps to 1.12x in step with the wall rate. Pitch
  and tempo move together, which is the point — it should read as the round getting frantic.

`Arena.seal_cell()` clears whatever was on the cell: a block goes without its usual powerup roll
(the wall would bury it anyway), a powerup is removed, and a bomb is *detonated* rather than
deleted, so its owner gets the charge back instead of being down a bomb for the rest of the round.

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
- Mine / remote bomb / fire bomb weapon pickups from the brief aren't built.
- Team color tinting is whole-sprite (see Art pipeline) — not as clean as a clothes-only tint would
  be, but PixelLab doesn't hand back separable layers.
