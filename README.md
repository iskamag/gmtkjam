# Chronosword's Last Day — prototype

A first-person combat prototype for the GMTK theme **Count Down**.

The broken watch is the player's health:

- Its hand constantly ticks backward.
- Eliminations rewind the current time toward the watch's remaining maximum.
- A wound is automatically undone, but the rewind costs time and permanently
  breaks away part of the maximum.
- When the watch reaches zero, the chronosword's time has come.

The current opening is a short in-engine train ride, crash, trauma recovery, and
`EPILOGUE / THE FIRST JOB` handoff. Mouse look remains free throughout the
carriage and crash, and the windows show a separately moving sealed tunnel
rather than exposing the combat map. Playable time does not begin until control
returns.

## Controls

| Input | Action |
| --- | --- |
| `WASD` | Move |
| Mouse | Look |
| `Shift` | Chronostep (one air use before landing) |
| `Ctrl` | Ground slide; jump out to preserve speed |
| Left mouse | Buffered dagger combo / deflect; punch while unarmed; reflected shots get tight crosshair assist |
| `E` | Kick / guard break / launch; punt hostile projectiles with wider crosshair assist |
| Right mouse | Free throw (hold briefly to guide); press again to pay Watchfire for rewind |
| `Q` | Arrest hostile time; a last-instant activation earns a Dead Second |
| `Space` | Jump / slide-jump / wall-kick |
| `Space` during opening | Skip to the identical post-crash gameplay state |
| `F3` | Prototype telemetry |
| `R` | Restart after death |
| `Esc` | Release/capture mouse |

## Run

```sh
godot --path .
```

## Browser export

For a one-command export and local server:

```sh
./play-web.sh
```

The launcher resolves its own project directory, exports into a new build-ID
directory, prints the exact cache-busted URL, and serves every file with browser
caching disabled. If port 8000 belongs to an older preview, it automatically
selects a fresh port instead of silently leaving you on the old game.

Or run the individual steps:

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server --directory build/web 8000
```

Then open `http://localhost:8000`. The game uses Godot's Compatibility renderer
and the non-threaded web template.

The full design record and explicit rejected directions are in
[`DESIGN.md`](DESIGN.md). The complete influence map, art laws, texture
references, and measurable smoothness contract are in
[`REFERENCE_DNA.md`](REFERENCE_DNA.md). The license-traceable production
moodboard and local-asset map are in [`AESTHETIC_BOARD.md`](AESTHETIC_BOARD.md).
Every shipped engine, font, sound, model, texture, supplied shader, and optional
commercial-pack dependency is recorded in [`ATTRIBUTION.md`](ATTRIBUTION.md);
browser builds place that file and the redistributable license notices beside
the game.

## Optional supplied art

The game automatically uses a small locally supplied Polyperfect apocalypse set
when it exists at `assets/user_pack/`: a derailed train, rail, rubble, ruined
town landmarks, lamps, barriers, and their albedo, night-emission, and specular
atlases. A dedicated night material preserves lit windows and separates dull
wall, glass, and metal response instead of flattening the pack to one rough
albedo. The route, collision, and procedural dressing remain playable without
the optional models.

This makes the art boundary explicit: replace world presentation without
touching encounter or movement logic. Enemy gameplay is likewise separated from
its `DeferredBody` visual child, and the first-person hands are isolated in
`scripts/hands_2d.gd`.

## Rendering boundary

The browser build uses Godot's Compatibility/WebGL 2 renderer. It uses Filmic
tonemapping, a code-authored layered cloud/star sky, restrained glow, emissive
highlights, fog, temporal history samples, and event-linked distortion. Browser
output is SDR; it does not claim true HDR display output.

## Scope

This is a mechanics slice, not a content-complete jam submission. It contains a
short sequence of encounters and a boss-shaped finale to test:

1. kill-based time recovery;
2. wound rewind plus permanent maximum-time erosion;
3. momentum movement, slide-jumps, wall-kicks, and a time-art chronostep;
4. buffered melee, unarmed stagger, launch, blade deflection, high-force
   projectile kicks, hit-stop, and enemy reactions;
5. free steerable dagger placement, expensive manual recall, and free physical
   retrieval;
6. gated authored encounters and PS2-style historical deterioration rather
   than posterization;
7. perspective-correct world damage numbers plus a long non-numeric status bar
   separating current life, recoverable time, and permanently eroded capacity;
8. authored enemy manifestation, predictive multi-shot pressure, denser mixed
   roles, geometric projectile families, and an
   action-native train-crash epilogue opening.
9. ordinary Watchfire dominance plus a timing-earned Dead Second that nearly
   arrests threats while accelerating the chronosword's movement, attacks, and
   damage, without allowing ordinary slowed-time melee to refill the ability
   forever.
10. a three-phase boss with downward arena cuts, close-pressure reinforcements,
    a related late-game-scale health bar, and combat rays that respect solid
    cover.

The project emits neutral gameplay signals for future score choreography. It
deliberately does **not** contain a shallow adaptive-music mixer. A genuinely
dynamic score must be composed around its transition graph, sync points, musical
cells, stems, fills, and stingers.

Current neutral score hooks include `intro_black`, `train_rhythm`,
`status_reveal`, `memory_intrusion`, `crash_premonition`, `crash_hit`,
`title_epilogue`, `control_return`, `encounter_started`, `encounter_cleared`,
`boss_started`, `boss_phase`, `player_hit_confirmed`, `projectile_kicked`,
`watch_state`, `watch_overclock`, `overclock_hit`, `dagger_state`, and
`time_expired`. They are presentation events, not an assumption about how the
user's track must be arranged.
