# Asset attribution

## Godot Engine

- Project: Godot Engine
- Source: <https://godotengine.org/>
- Copyright: Godot Engine contributors; Juan Linietsky and Ariel Manzur
- License: MIT
- Repository license copy: `LICENSES/Godot.txt`
- Browser-build license copy: `licenses/Godot-MIT.txt`
- Full component copyright and third-party license notices:
  `LICENSES/Godot-Third-Party.txt` in the repository and
  `licenses/Godot-Third-Party.txt` beside browser builds.
- Used for: engine runtime, renderer, browser export template, scene and audio
  systems.

## Godot Engine logo

- Creator: Andrea Calabró
- Copyright: 2017, Andrea Calabró
- License: Creative Commons Attribution 4.0 (CC BY 4.0)
- Used for: Godot's default browser icon and loading splash.
- License and attribution copy: the `Godot Engine logo` entry and
  `CC-BY-4.0` text in `Godot-Third-Party.txt`.

## Kenney Prototype Kit

- Creator: Kenney
- Source: <https://kenney.nl/assets/prototype-kit>
- License: Creative Commons Zero (CC0 1.0)
- Repository license copy: `assets/kenney/License.txt`
- Browser-build license copy:
  `licenses/Kenney-Prototype-Kit-CC0.txt`
- Used for: modular architectural props, industrial dressing, figurine meshes,
  and the source sword mesh.

The game code, procedural first-person view models, materials, and shader effects
in this repository were authored for this prototype. The event-linked
crash/time-scar treatment was adapted from `wobbly.gdshader`, supplied by the
project author from their own Clicking Galaxies project.

## Kenney Impact Sounds

- Creator: Kenney
- Source: <https://kenney.nl/assets/impact-sounds>
- License: Creative Commons Zero (CC0 1.0)
- Repository license copy: `assets/audio/License.txt`
- Browser-build license copy:
  `licenses/Kenney-Impact-Sounds-CC0.txt`
- Used for: dagger impacts and recall, barehanded hits, Watchfire activation,
  and broken-watch wound feedback.

No generated visual or audio assets are included.

## Poly Haven — Worn Asphalt

- Source: <https://polyhaven.com/a/worn_asphalt>
- Creator: Poly Haven
- License: CC0 1.0
- Files used: 1K diffuse, OpenGL normal, and ARM texture maps under
  `assets/textures/polyhaven/`.
- Use: the wet return road beneath the combat route.

Poly Haven's asset license is available at <https://polyhaven.com/license>.

## Barlow Condensed

- Source: <https://github.com/google/fonts/tree/main/ofl/barlowcondensed>
- Copyright: The Barlow Project Authors
- License: SIL Open Font License 1.1
- File used: `assets/fonts/BarlowCondensed-SemiBold.ttf`
- Repository license copy: `assets/fonts/BarlowCondensed-OFL.txt`
- Browser-build license copy: `licenses/Barlow-Condensed-OFL-1.1.txt`
- Use: interface, clear-data, encounter, and ending typography.

The photographs under `references/moodboard/` are non-exported design
references, not game textures. Their individual authors, source pages, licenses,
and translation notes are recorded in `AESTHETIC_BOARD.md`.

## Optional local apocalypse set

The local prototype can use a small selection from **Low Poly Ultimate Pack**
by Polyperfect (Unity Asset Store package 54733): the derailed train, rubble,
ruined house/café, road lamp, and their shared albedo, night-emission, and
specular atlases.

These are user-supplied commercial Asset Store files, not CC0 assets. Their raw
source files are ignored by Git and the game has procedural fallbacks when they
are absent. A distributable game export may include them only under the user's
valid Asset Store entitlement and the package's license. Do not redistribute
the source pack as a general asset library.

`play-web.sh` places this attribution file and the redistributable license
notices beside every browser build. The same notices are also explicitly
included by the Godot export preset so a manually produced package retains them.
