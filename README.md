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
| `Shift` | Chronostep (one air use before landing) |
| `Ctrl` | Ground slide; jump out to preserve speed |
| Left mouse | Buffered dagger combo / deflect; punch while unarmed |
| `E` | Kick / guard break / launch |
| Right mouse | Free throw (hold briefly to guide); press again to pay Watchfire for rewind |
| `Q` | Burn Watchfire to slow hostile time |
| `Space` | Jump / slide-jump / wall-kick |
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
[`DESIGN.md`](DESIGN.md).

## Scope

This is a mechanics slice, not a content-complete jam submission. It contains a
short sequence of encounters and a boss-shaped finale to test:

1. kill-based time recovery;
2. wound rewind plus permanent maximum-time erosion;
3. momentum movement, slide-jumps, wall-kicks, and a time-art chronostep;
4. buffered melee, unarmed stagger, launch, deflection, hit-stop, and enemy
   reactions;
5. free steerable dagger placement, expensive manual recall, and free physical
   retrieval;
6. gated authored encounters and PS2-style historical deterioration rather
   than posterization;
7. the level-50 damage-number presentation without a conventional HUD health bar.

The project emits neutral gameplay signals for future score choreography. It
deliberately does **not** contain a shallow adaptive-music mixer. A genuinely
dynamic score must be composed around its transition graph, sync points, musical
cells, stems, fills, and stingers.
