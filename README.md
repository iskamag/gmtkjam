# Chronosword's Last Day — prototype

A first-person combat prototype for the GMTK theme **Count Down**.

The broken watch is the player's health:

- Its hand constantly ticks backward.
- Eliminations rewind the current time toward the watch's remaining maximum.
- A wound is automatically undone, but the rewind costs time and permanently
  breaks away part of the maximum.
- When the watch reaches zero, the chronosword's time has come.

## Controls

| Input | Action |
| --- | --- |
| `WASD` | Move |
| Mouse | Look |
| Left mouse | Dagger combo / deflect; punch and kick while unarmed |
| Right mouse | Throw dagger; press again to rewind it manually |
| `Q` | Burn Watchfire to slow hostile time |
| `Space` | Jump |
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

The launcher resolves its own project directory, rebuilds the Web export, prints
a cache-busted URL, and serves every file with browser caching disabled.

Or run the individual steps:

```sh
mkdir -p build/web
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server --directory build/web 8000
```

Then open `http://localhost:8000`. The game uses Godot's Compatibility renderer
and the non-threaded web template.

The full design record and explicit rejected directions are in
[`DESIGN.md`](DESIGN.md).

## Scope

This is a mechanics slice, not a content-complete jam submission. It contains a
short sequence of encounters and a boss-shaped finale to test:

1. kill-based time recovery;
2. wound rewind plus permanent maximum-time erosion;
3. melee, unarmed stagger, deflection, steerable throw/manual recall, and
   Watchfire slowdown;
4. PS2-style authored spaces and historical deterioration rather than
   posterization;
5. the level-50 damage-number presentation without a conventional HUD health bar.

The project emits neutral gameplay signals for future score choreography. It
deliberately does **not** contain a shallow adaptive-music mixer. A genuinely
dynamic score must be composed around its transition graph, sync points, musical
cells, stems, fills, and stingers.
