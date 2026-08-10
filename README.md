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
- **Map**: which terrain the arena is carved into — Classic, Bridges, Crater, Quarters, Plaza, or
  Random (the default, re-rolled every round). See [Maps](#maps).
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
- The results overlay between rounds leads with the winner *as a character*: their own sprite, blown
  up big in their team color and walking on the spot, with the character's name under it — "Player 2"
  alone stopped meaning much once everyone started re-picking between rounds. The whole block shrinks
  as one piece on a window too short to hold it. A draw shows the text only.
- **The match actually stops when it's over.** `Main._on_round_ended` used to call
  `GameManager.reset_match()` + `reload_current_scene()` unconditionally at the end of every round,
  match-over included — which zeroed `round_number` back to 0 and dropped straight into a fresh round
  1 with the same players, so a "5-round match" never actually ended, it just kept dealing itself
  another one forever. The last round's results now stay up and, if anyone human is in the match,
  hand off to a small **Restart / Lobby / Quit** menu (`Main._show_match_over_menu`) instead of
  auto-continuing — any connected device may drive it, the same "nobody owns this screen" rule
  `MainMenu.gd`'s title screen uses. Restart calls the same `reset_match()` + reload as before, now
  gated behind an actual choice; Lobby is `GameManager.leave_to_lobby()` (the same transition the
  pause menu's own exit option uses); Quit exits outright. A match with nobody there to press a
  button — every slot a bot, or every pad gone — has no menu to get stuck on: it falls back to the
  old timed countdown, just landing on the Lobby now instead of quietly restarting.
- The **pause menu** shows the running score in the corner for as long as it's open
  (`PauseMenu._refresh_score`) — pausing mid-match is exactly when someone wants to check it, and the
  alternative (catching it during the few-second between-round overlay) is gone before most people
  think to look.

## Status (MVP priority list)

- [x] 1. Grid movement + base bomb + destructible blocks
- [x] 2. Local multiplayer — Lobby join flow (up to 4, keyboard + gamepads), mid-match disconnect/reconnect handling
- [x] 3. Rounds/score UI — results overlay between rounds, configurable match length, match winner by
  score with a Restart/Lobby/Quit menu on the final screen
- [x] 4. Character roster + abilities — Bomb-Master, Parkour Runner, Engineer, Pyro, Bomb-Kicker, Magnetto, Miner, Grenadier (8 characters; brief listed 4, the rest added per later requests)
- [~] 5. Powerups — bomb count/radius/speed/shield drop from blocks and sit on the ground until collected (bobbing icon, never destroyed by blasts); extra weapon *pickups* (mine/remote/fire bomb) not yet built
- [~] 6. Art & audio — AI-generated (PixelLab) pixel-art characters with walk animations, HUD/pickup icons, pause menu icons, blocks, walls, explosions, temp wall all done. Procedural sound effects and two music loops are in; no voice/announcer.
- [x] 7. Sudden death — a round that drags past the round-end timer (default 2 minutes) gets walled in from the outside
- [x] 8. Map layouts — Classic, Bridges, Crater, Quarters, Plaza; by default every round is on a different one

## Characters

| Character | Passive | Ability (ability button) |
|---|---|---|
| Bomb-Master (Сапёр) | +1 bomb, +1 shield, from the start | **No fuse at all** — every bomb you place is a remote mine (blinking antenna, no ticking Timer) that only goes off when you press this |
| Parkour Runner (Паркурщик) | +25% move speed, +1 shield | Double-tap a direction to hop over a crate, a bomb, **or an indestructible wall** (no button) |
| Engineer | +1 bomb | Place a temp wall (12s) on your own cell — passable for you only, destroyed early by a blast. **One wall per bomb you have** |
| Pyro | +1 shield, +50% powerup drop chance, walks through their own bombs | Every bomb explodes in a diamond and punches through crates |
| Bomb-Kicker (Хокеист) | +10% move speed, +1 shield, and skating: unbroken straight-line running charges speed up to 1.6x over 0.8s | Kick the bomb in front of you **2 cells** (+1 per speed powerup, `Player.kick_distance`), or until it hits an obstacle; it can still explode mid-slide |
| Magnetto (Магнетто) | +1 bomb, +1 shield | None — their bombs crawl a cell at a time toward whichever opponent is nearest, waking only inside 8 cells and lunging on the last two |
| Miner (Минёр) | +1 bomb, +1 shield | Spend **two** charges to plant an invisible mine: no fuse, walkable, and set off by any opponent stepping anywhere its (half-radius) blast reaches |
| Grenadier (Гранатомётчик) | +1 shield, and **no bombs at all** — the launcher replaces them | Lob a shell in the direction you face, over walls, crates, water and people alike; it explodes the moment it lands, wherever it lands. **Tap** the bomb button for 2 cells with the blast shrunk to fit, **hold** it to paint in a dial at your feet and walk the shot out to 3 cells (+1 per bomb powerup), the blast growing with the distance — but holding plants you |

The Sapper's mines stay live until triggered — by the ability button, or by chain-detonating in
someone else's blast — with no timeout of their own, so `bomb_count_current` doesn't refill until
one actually goes off (`Bomb.remote`, set in `Player.place_bomb()`; `Bomb._ready()` skips starting
the fuse Timer entirely for one). A Sapper who dies holding unplaced charges leaves live mines
sitting on the map for the rest of the round, blocking their cell like anyone else's bomb, until
another blast reaches them.

The wall-hop is what makes the Parkour Runner the one character who isn't fighting the map's fixed
layout: everyone else treats the checkerboard/random indestructible walls as permanent, but a
double-tap clears a single-thick one same as a crate. A double-thick wall or the arena's outer ring
still isn't jumpable — the landing cell has to be open ground, and there the hop just fails.

Every character also biases the powerups dropped by the crates *they* break toward the stat their
kit scales on (Pyro → radius, since the diamond grows as an area; Parkour Runner → speed;
Sapper/Engineer/Hockey → bomb count). The bias only
redistributes a fixed drop chance between the four types, so the number of powerups on the map is
unchanged — raising the *total* is Pyro's alone.

The skating charge resets the instant the run breaks — a turn, a released stick, or walking into a
wall — so it pays for committing to a whole corridor and gives nothing back in the tight weaving
where the rest of the roster is tuned. It was added (with the shield) because kick-only was too thin
a kit to be worth picking.

Balance note: Pyro was the only character with a compounding advantage (more powerups → more bombs →
more crates broken), so the rest of the roster was brought up to it rather than Pyro brought down.
The Engineer was the worst off — no passive at all, and a single minute-long wall — and got the
biggest share of that: a starting bomb, a wall budget tied to their bomb count, and a wall lifetime
short enough that more walls doesn't mean a permanently redrawn map.

The Grenadier is the only ranged attack in the game, and the only character with **no ordinary
bombs**: the launcher replaces them outright (`Player._can_place_bombs`), so it lives on the *bomb*
button and the ability button does nothing for them. (It threw as well for a while. Two buttons
doing one thing invites holding one and tapping the other, which cancels your own charge.)
Everything about the shot is built to keep it from being artillery.

How far it goes is the one thing the player controls, and it is set by how long the button is held
rather than by aiming:

- A **tap** throws two cells and shrinks *that shell's* blast to whatever fits in the gap
  (`Player._grenade_shot_radius`): two cells away can only ever be a radius-1 blast, three cells buys
  radius 2, and so on up to the launcher's own. So a tap is safe to take at any radius — a Grenadier
  with a big blast still lobs one right in front of themselves instead of being pushed further out by
  their own upgrades — and charging buys power as well as reach, since the only way to throw your
  whole blast is to throw it properly far.
- **Holding** paints in a dial at the Grenadier's feet over `Player.GRENADE_CHARGE_TIME` (0.6s) and
  walks the landing cell out to `GRENADE_CHARGED_RANGE` (3), the fixed range the character shipped
  with. Holding also **plants them**: they can still turn (the launcher is aimed by facing) but not
  walk, so a charged shot is taken from where it was started rather than carried into position with
  the shot already loaded.
- Every **bomb** powerup adds a cell to that ceiling, because a character with nothing to put on the
  floor has no other use for one — their charges are shells in the air, and the cooldown means there
  is never more than one. Reach is therefore what a Grenadier grows, and the only upgrade in the game
  that grows an ability rather than the body carrying it; the HUD's bomb pip counts reach for them.
  Speed stays out of it and buys them only what it buys everyone — a character who has to stand still
  to charge shouldn't be turning legs into artillery range as well.

The dial has two states and they can never both be on screen, because a charge is refused while the
launcher is hot. Charging, it is orange and paints in **clockwise** from twelve o'clock, one slice
per cell of extra range with a spoke between slices — what it reports is which cell the shell lands
on, so a smooth sweep would imply a precision the grid hasn't got, and a full circle of colour is
this Grenadier's longest throw. On cooldown it is red and unwinds **anticlockwise**: the charge
running backwards, drained to nothing at the moment the launcher is ready again.

The shell is then in the air for `Bomb.flight_time_for()` — 0.22s per cell, floored at 1.1s — with a
ring drawn on its landing cell for the whole flight. Even the shortest shot is three and a half
cells of walking at base speed, which is the entire counterplay: a shell aimed where somebody *is*
misses, one aimed where they are going does not. The floor is deliberately generous, because a shell
lobbed over the crate somebody is hiding behind arrives with the least warning of any of them.
Pricing the rest by distance is what stops the charged shot from being strictly better than the tap:
it reaches further, but it hangs in the air longer and is that much easier to walk out from under.

On top of the per-shot cap, the launcher only ever has **half** the radius its thrower has picked up
(`Player._grenade_radius()`), so a radius powerup is worth exactly half as much to it as to a bomb on
the floor — a full-strength blast on a shell you can drop three cells away with no risk to yourself
would otherwise be the best thing in the game. Between the two rules a shell can never cover the cell
it was thrown from, and the shot is refused outright in any case where the arena says it would.

A shell still costs a bomb charge and hands it back when it goes off, which keeps it inside the same
accounting as everyone else's ordnance, but with nothing else drawing on the pool that single base
charge is never what stands in the way. The **cooldown** is, and it is counted **from impact rather
than from the throw**: `Player.GRENADE_COOLDOWN` (1.2s) is added to that shot's flight time, so the
tube is busy for as long as something is in the air and 1.2s after it lands. A tapped shot therefore
comes round every 2.3s and a long one every 2.5-3s, about the pace of everyone else's bombs; at half
of that it read as spamming shells rather than picking shots. Measured from the throw instead, any
cooldown shorter than the flight would put two shells in the air at once, which is a different and
much less answerable character.

**Nothing stops a shell**, at either end. Crates, water, bombs, people and stone are all flown over,
and a shell aimed at a wall goes off *on* the wall, its blast spreading out of the impact into
whatever open ground is beside it. It used to walk the landing cell back to the last non-wall cell,
which is tidier in the abstract and unreadable in play: on the default checkerboard, aiming along an
even row meant the shell quietly landed a cell nearer than the dial had just promised, for a reason
nothing on screen explained. The only thing still walked back is the edge of the map, since out
there is no cell to land on at all.

A shell in the air is deliberately **not on the grid**: it doesn't block the cell it is about to land
on, can't be kicked or chained on the way there, and comes down on top of a mine without erasing it.
Bots see it anyway, off its owner's `live_bombs` (`Player._incoming_shell_cells`), and unlike
everything else they react to they check for one **every frame** rather than on their decision tick —
a shell lands in less time than one interval, and a bot that waited its turn would be informed of the
shot by the explosion. Finding one aimed at the cell they are standing on *or walking toward* throws
away the heading they were holding and forces a decision on the spot, after which the ordinary flee
handles it. Bots aimed at directly now walk clear of roughly two shells in three, against one in
three before.

Bombs chain-detonate: any blast that reaches another bomb sets it off immediately too.

## Art pipeline

Characters, icons, and props are generated through the **PixelLab MCP server** (`mcp__pixellab__*`
tools), not hand-drawn. Each character is a single flat-shaded sprite per direction —
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

Three characters are **re-skins** rather than generations, because the trial account is nearly out
(`get_balance`) and a character's own sheet costs 5: the Magnet is the Engineer's frames with the
hard hat restyled, the Miner is the Engineer's with a camo helmet and visor, and the Grenadier is
the Miner's in olive drab with a shouldered launcher drawn on. Only the last of those has its script
kept — `tools/grenadier_sprites.py`, run from anywhere, writes all 28 frames from the Miner's and is
where the launcher's size, angle and colours live. Note that it reads the Miner's sheet at build
time, so re-skinning the Miner again would change the Grenadier under it.

Regenerating art means re-running the PixelLab MCP calls (`create_character`, `animate_character`
with `template_animation_id="walk"`, `create_image_pixen`, `edit_image`) — nothing but the re-skin
script above runs locally, and the trial account has a hard cap on generations (`get_balance`), so budget before batching a lot
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

## Maps

The **Map** row on the Lobby's settings screen picks the arena's *terrain*. It is separate from
**Map size** (which only sets the grid) and from **Random walls** (which swaps the checkerboard of
fixed pillars for scattered ones): a layout is carved on top of whichever base pattern those two
produce, so every layout works at every size and in either wall mode.

The default is **Случайно / Random**, and it re-rolls **every round**, not once per match — a match
walks through the set instead of settling on one map. It deals rather than rolls: every layout that
fits the grid is played once before any of them comes up again, and a fresh deal never opens on the
one that just played, so no two rounds in a row are on the same map. (An honest per-round roll
repeated itself about one round in five, and a five-round match that played Crater three times read
as the setting being broken.) Whichever map came up is named on screen for
the first 3 seconds of the round, since otherwise the terrain changing under everyone reads as the
game being inconsistent rather than as the setting doing what it says.

| Map | Terrain |
|---|---|
| Классика / Classic | Nothing carved — the map this game has always had. |
| Мосты / Bridges | A chasm splits the arena down the middle; two bridges are the only way across. |
| Кратер / Crater | A ring of chasm around a small central plateau, with four bridges in. |
| Кварталы / Quarters | A solid wall cross cuts the arena into four rooms joined by four doorways. |
| Площадь / Plaza | The centre is swept clear of everything and the crates pile up around it (85% density). |

Layouts are gated on grid size rather than offered everywhere and quietly degrading — a chasm
splitting a 9x7 arena leaves two rooms of a dozen cells, which isn't a smaller version of the same
map but a worse one. Anything that doesn't fit falls back to Classic, including inside a Random roll.

### Chasms and bridges

A chasm (`CellState.CHASM`) is a **hole, not a wall**, and the distinction is load-bearing:

- Nobody crosses it, and neither do bombs — a kicked or magnet-crawled bomb stops at the water's edge.
- **Blasts fly straight over it.** A river that also stopped explosions would turn Bridges into two
  arenas that never touch until somebody walks across; the crossings are meant to create a standoff,
  not enforce one.
- **The Parkour Runner can hop it.** A chasm is a one-cell obstacle with open ground behind it, so
  the double-tap hop clears it exactly like a crate or a stone pillar does. On the water layouts that
  is the character's whole edge: the only one a blown bridge doesn't strand.

A bridge is one chasm cell with a crossing over it. Intact it is ordinary floor and reads as such to
*everything* — players walk it, bombs slide over it, the bots' pathfinder routes through it — and
any explosion that reaches it drops it back to the chasm underneath. It then rebuilds itself **25%
every 5 seconds** and is walkable again only at the last quarter: a bridge is either there or it
isn't. A fresh blast resets the progress to zero outright, so holding a crossing down is something
you have to keep spending bombs on. How much is left to close is drawn rather than metered — the
deck grows in from both banks, and the gap in the middle *is* the repair bar.

When a crossing goes down it takes what was standing on it: a powerup is removed, and a bomb is
detonated rather than deleted so its owner gets the charge back. Players are the exception —
`Player._unstick()` already walks anyone off a cell that has stopped being legal, so a collapse is a
shove to the nearest bank rather than a drowning. Generation guarantees both banks of every bridge
are open ground (a crossing that opened onto a crate or a random wall would be one in name only),
and the connectivity guard that protects Random walls treats chasms as closed, so a map is never
generated already split. It can of course *become* split mid-round, which is the layout working.

## Sudden death

A round that runs past the **Закрытие раунда / Round end** setting (default 2 minutes) starts closing
in (`scripts/SuddenDeath.gd`, a node on `Main`).
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
It also retires any bridge on that cell, so a crossing the ring has just filled in stops rebuilding
itself. Open water is skipped by the spiral outright — it is impassable already, so sealing it would
spend a turn of the ring without taking a cell of ground off anyone.

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
  the multi-second fuse gives time to walk clear).
- Bots also play their character's ability, not just its passives — added once the Sapper's trigger
  and the Engineer's wall-per-bomb scaling made the ability half the kit rather than a bonus on top
  of it. Each is character-specific and sits in its own `_bot_try_*` method in `Player.gd`: the
  **Sapper** detonates every bomb it has out the instant an enemy steps into one of their blasts —
  or, once it's safely clear, for a block-only blast too, since a Sapper's mines never go off on
  their own and skipping the block case would leave the bot holding dead charges for the rest of the
  round (only spends a shield on an enemy target, never on a block that isn't going anywhere); the
  **Engineer** drops a wall on itself when a chokepoint cell (≤2 open neighbours) sits within
  `BOT_WALL_ENEMY_RANGE` steps of an enemy, spaced out so its small budget doesn't get spent on one
  corridor twice; the **Parkour Runner** hops over a block/bomb/indestructible wall to clear a blast
  it's standing in, when a plain step can't; the **Hockey Player** kicks a bomb it's next to (which,
  since nothing can block a blast one cell from its source, only ever happens while it's *in* that
  bomb's blast) rather than just running, aiming down a lane at an enemy when one lines up. The first
  three run as an alternative to the generic flee the instant the bot is in danger; the Engineer's
  wall check instead runs on the normal wander/bomb decision, since placing one costs it nothing.
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
