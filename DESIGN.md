# Chronosword's Last Day

## Status

This document records the design discussed on 24–25 July 2026. It is the source
of truth for the prototype. When an implementation choice contradicts this file,
the implementation is wrong.

## One-sentence pitch

**A short first-person action thriller about a level-50 chronosword spending,
stealing, and burning the final scraps of an unavoidable life while completing
the first job they once left unfinished.**

## Theme

GMTK Jam theme: **Count Down**.

The countdown is not an ornamental mission timer. It is the player's life.
It is always running backward on a broken analog watch held in the left hand.

The player can steal back current time by eliminating enemies, but wounds
permanently reduce the watch's maximum. Recovery therefore prolongs the last
job without offering immortality. There are finitely many enemies and no route
to tomorrow.

## Tone and fantasy

- Thriller, not a power-comedy.
- An impending and inescapable sense of doom.
- The protagonist is extremely capable and extremely mortal.
- Modern and fantasy elements coexist without becoming generic cyberpunk.
- The world should feel like a missing late-game chapter from a larger,
  half-remembered RPG.
- Nightmare imagery corrupts familiar places and game grammar. It is not a
  collection of generic glitch, VHS, liminal-space, or creepypasta filters.
- The story is sincere. Weirdness is allowed to be emotionally direct.

The chronosword is comparable to a spellsword: a warrior trained in a lost art
that manipulates time. A chronosword does not erase consequences. They postpone
them. On the final day, postponed events return.

## Story

The game begins aboard a late train after the protagonist's unseen grand
adventure. They are already level 50, already famous or feared, and already at
the end of their life. A sparse clear-data/stat readout makes the player enter
the epilogue of an RPG that never existed.

The train begins almost peacefully. Its rhythm and the indistinct sounds of old
encounters accumulate. Something postponed catches up with the carriage. The
chronosword's power lets them survive the crash by reflexively rewinding the
wound, but the low-health red clears to reveal that the analog watch is broken
and already ticking backward. Control returns as they climb from the wreck into
a familiar town. **EPILOGUE** appears. The countdown begins here, after the
short authored opening, so the cinematic does not steal playable time.

The chronosword's first assignment was a creature they were too inexperienced
to kill. They cut the encounter out of the present and postponed it until they
were strong enough. They never returned.

Now the chronosword is dying. Their magic is failing, and postponed pieces of
their career are re-entering the world. They choose one final job: return to
that first unfinished encounter, kill the creature, and then go home.

The final boss is not Death. It does not control the protagonist's lifespan.
There is no government conspiracy, corrupt institution, secret cure, loop, or
rebellion. Completing the job cannot prevent death.

Defeating the boss restores the watch as much as it can still be restored. With
no enemies left to kill, the hand continues ticking backward through the final
walk. Midnight/zero is the ending, not a villain to defeat.

The opening must remain action-native: roughly ten seconds, skippable after its
first second to the identical post-crash state, no dialogue tree, no lore
panel, and no long loss of control.

## Reference DNA

The intention is not to copy the surface of any one reference. The useful shared
qualities are:

- fast expressive movement and immediate controls;
- fragile play supported by powerful defensive options;
- fighting-game and shmup readability: telegraphs, patterns, timing, cancels,
  positioning, and mastery;
- short runs worth replaying;
- sincere narrative inside abrasive, strange, or nightmare worlds;
- the feeling of finding a relic from a lost era of games;
- tightly controlled sensory overload rather than undirected visual noise.

Discussed references include Rogue Legacy; Team Ladybug and Game Bakers games;
Ori; Slayin 2/DX; Watch Dogs 1; The Desolate Hope; Picayune Dreams; Don't
Starve; Fearless Fantasy; Copy Kitty; The Binding of Isaac; The End Is Nigh;
Titanfall 2; Type:Rider; shmups and fighting games; Post Void; Super Hexagon;
VVVVVV; Undertale; RuneScape; Cat Quest; Dicey Dungeons; The Escapists; Plants
vs. Zombies; Spelunky; Viocide; Kitten Burst; Rayman Legends; Super Cat Tales;
Wizard Drop Tower; Shovel Knight; Sonic; Prince of Persia: The Sands of Time;
The Stick of Truth; Osmos; Knightmare Tower; EXIT PATH; and Bayonetta.
Ninja Gaiden on PS3 is an explicit combat and presentation reference.

Other relevant personal concepts:

- Iris: a fragile third-person parkour action heroine using a lost time-slowing
  art and a blade empowered by collected blood.
- The last child of a tyrannical lineage: a fragile, checkpointless ascent
  through a megatower over one compressed in-game day.

Chronosword must not simply become either of those games. First person, the
diegetic watch, stolen time, and a manually rewound dagger distinguish it.

The complete taste map, translation rules, palette, texture references, and
smoothness contract live in [`REFERENCE_DNA.md`](REFERENCE_DNA.md).

## Format

- First-person 3D action.
- Browser-playable.
- Godot Compatibility renderer for the current prototype.
- Short continuous run; target jam length roughly 10–15 minutes.
- One connected, authored location rather than an abstract sequence of arenas.
- Fast restart.
- Public/licensed asset libraries for source art and audio.
- Original implementation, shaders, choreography, and game code are permitted.

## Design pillars

### 1. The watch is the health bar

There is no separate conventional player health bar.

- The watch is analog. It has hands and tick marks, never a numeric display.
- Its main hand constantly moves backward.
- A kill winds the current hand forward, up to the remaining maximum.
- Being wounded triggers an instinctive rewind of the wound.
- Rewinding a wound spends a large piece of current time.
- Every wound also breaks the mechanism and permanently reduces maximum time.
- The lost maximum is visible as missing/broken portions of the watch rim.
- The wound rewind affects the body, not the player's location. It must not
  teleport the player backward.
- The hit response is concentrated in the hands and watch: recoil, a violent
  hand movement, the watch hand whipping backward, and another piece breaking.
  Avoid full-screen inversion and arbitrary glitch tearing.

### 2. Level-50 action without progression bloat

The protagonist begins complete.

- No skill tree, loot rarity, crafting, inventory management, or levelling.
- Damage values are in the thousands.
- The moveset supports cancels and combination from the first encounter.
- Enemies have late-game attack patterns and meaningful pressure.
- The protagonist can be fragile even though the numbers are enormous.
- Large damage numbers appear in world space, rise above the target, and vanish,
  in the spirit of Hotline Miami score feedback.
- Screen-space UI remains sparse.

### 3. The dagger has an absence state

The right-hand weapon is a dagger, not a gun and not a passive boomerang.

Held:

- quick melee sequence;
- final/heavy hit provides stronger stagger or knockback;
- can strike/deflect suitable projectiles.

Thrown:

- throwing is an explicit input and is free;
- holding the throw input briefly steers its outbound course with the player's
  aim;
- after the short guided interval it becomes a fast ballistic object with
  gravity and must embed in geometry rather than hover;
- it records its travelled path;
- it does not automatically return on a timer;
- another input spends a substantial amount of Watchfire to rewind it manually
  through its recorded path;
- rewind cost scales with the path length, so it cannot be treated as an
  effectively free infinite ranged attack;
- the rewind path can damage targets again;
- a stuck or resting dagger can be physically picked up for free by reaching
  it, providing the no-meter fallback;
- while the dagger is absent, the right hand visibly becomes unarmed.

Unarmed:

- the attack sequence becomes punches and a kick;
- unarmed range is shorter and riskier;
- it remains useful, particularly for stagger, knockback, or building flame;
- the player is never left with a dead attack button.

This creates the central combat decision: keep the reliable melee tool, or place
the dagger in the world and fight barehanded while constructing a lethal rewind
path.

### 4. Watchfire is an embodied meter

Watchfire is not primarily a HUD bar or percentage.

- It appears as an actual deep-purple flame rising from the left hand/watch.
- Flame height communicates stored meter.
- Successful close combat, deflection, and eliminations build it.
- Holding the ability burns it to control hostile time.
- Manually rewinding the dagger spends a large up-front portion of it; throwing
  and physical retrieval do not.
- Activation must be unmistakable: the left hand raises, the fire becomes
  violent, enemies/projectiles slow heavily, and the world presentation reacts.
- Purple is deliberate but must not become neon cyberpunk sludge.
- Watchfire and the life countdown are separate resources.

The economic choice is concrete: burn flame over time to control a dangerous
moment, or reserve enough to recall a deliberately placed dagger. If neither is
affordable, close combat and physical retrieval remain available.

### 5. Movement belongs to the chronosword

- The problem with the first dash was its generic arena-shooter packaging, not
  the existence of a burst-movement verb.
- Running preserves readable momentum and supports strong air steering.
- Ground slides preserve speed; jumping out of one creates a long jump.
- Wall-kicks make the authored route and room edges part of combat.
- Chronostep is a short directional time-art burst with a ground/air cadence,
  recovery cancel, afterimage, camera shear, and no unrelated resource tax.
- The movement kit must support dagger retrieval, attack cancels, spacing, and
  authored traversal. It is not a checklist of references.
- Pure strafing must not produce an alternating camera or hand wobble. Camera
  lean follows intent quickly, settles without overshoot, and recentres quickly
  on reversal. Footfall bob is small, mostly vertical, and weighted toward
  forward travel.

### 6. Deterioration is historical, not graphical decay

This is a PS2-era 3D presentation, not PS1 posterization.

- No color quantization/posterization filter.
- No constant RGB split, VHS overlay, scanline gimmick, or generic glitch.
- No neon fog.
- Low-poly models, restrained materials, authored fog, strong silhouettes,
  limited draw distance, and deliberate animation produce the period feeling.
- The location must be identifiable: modern infrastructure intersecting old
  fantasy/ritual architecture. It must not resemble an empty backrooms arena.

As the day and the watch deteriorate, *specific past events and structures*
re-enter the place:

- obsolete architecture occupies the same site as modern construction;
- silhouettes repeat actions from old battles;
- dead or younger figures appear at meaningful positions;
- old attack patterns cross the present;
- materials and geometry show conflicting ages.

Deterioration should advance with the story/encounters and permanent damage,
not flicker backward every time an ordinary kill restores current time.

## Core loop

1. Enter a recognisable space carrying limited current time.
2. Read a small group of enemies and their attack pattern.
3. Choose between held-dagger safety and thrown-dagger path construction.
4. Fight, deflect, punch/kick, or burn Watchfire to control pressure.
5. Eliminate enemies to wind back the current hand.
6. Carry permanent watch damage into the next encounter.
7. Advance deeper as deferred pieces of the protagonist's history return.
8. Complete the boss job.
9. Experience the remaining countdown with no more time available to steal.

## Enemy and encounter principles

Enemies cannot merely run directly at the player while a ranged unit shoots.
Each role must create a different spatial question:

- **Arrears / rail collector:** a melee pursuer whose long committed cut returns
  along an old track; susceptible to spacing and stagger.
- **Signal witness:** a ranged attacker framed by a broken clock/signal halo. It
  fires stamped seal, vane, and fan patterns worth deflecting or routing the
  dagger through.
- **Buried retainer:** a post-game elite whose segmented guard rewards
  kick/recall combinations.
- **The Unfinished:** the first postponed job. It rises bodily through the
  asphalt and ballast; phases create openings through authored patterns and
  secondary threats rather than only inflating health.

The dagger's path, projectile patterns, Watchfire, and enemy positioning should
interact. Encounters should be arranged along the connected location instead of
spawning as interchangeable waves in a featureless room.

## View model and UI

- Both hands are 2D sprites/illustrations in front of the 3D world.
- Current prototype may draw them in code; final assets must come from permitted
  public sources or be created under jam rules.
- Left hand: broken analog watch plus rising Watchfire.
- Right hand: dagger, fist, or kick pose depending on combat state.
- No digital time text anywhere.
- No persistent Watchfire percentage.
- No player HP bar.
- Boss health bar is allowed.
- Small objective/title text is allowed.
- Damage numbers exist in 3D world space.
- Debug telemetry is optional and hidden.

## Visual direction

- Post-Void-like aggression is a pacing/composition reference, not a request to
  copy its palette.
- Doom total-conversion/mod feeling is welcome.
- PS2 rather than PS1.
- Modern fantasy: concrete, asphalt, utilities, faded institutional details,
  old stone, ritual machinery, blades, seals, and impossible clockwork.
- Palette: asphalt, dirty plaster, tarnished steel, old paper, faded blue,
  bruised brown, dead green-grey, dried rust, and controlled deep purple.
- No "neon slop."
- The watch uses noise, wear, missing casing, scratches, and broken mechanics
  rather than blood.
- Shader effects must communicate a gameplay or story state.
- Contact-localized time tears, brief channel misregistration, hit-stop, and
  cut planes communicate impact.
- Chronostep produces horizontal time shear and a fading history echo.
- Dagger rewind temporarily misaligns recorded rows and draws its actual path.
- Deferred architecture uses a world shader whose material becomes more
  coherent as permanent damage and encounter depth increase.
- These effects are transient or state-linked. There is no permanent
  posterization layer.

## Audio and future score choreography

The intended music system is not a four-state adaptive stem mixer.

It is a score-direction/choreography system in which room transitions, encounter
grammar, enemy health, player health/time, boss phase, movement beats, cinematic
events, motifs, fills, stingers, alternate continuations, and authored sync
points influence what the score is allowed to become next.

That requires a track composed as a graph of compatible musical cells and
transitions. Code cannot retrofit this depth onto a conventional loop.

For the jam prototype:

- do not build a shallow substitute and call it validated;
- emit neutral gameplay events that a future score director could consume;
- use a straightforward licensed/public track only if one fits;
- reserve the full system and purpose-authored score for Iris or a later
  Chronosword production.

## Asset and licensing constraints

- Do not use generated visual or audio assets if the jam rules forbid them.
- Generated game code is allowed.
- Prefer public asset libraries with clear licenses.
- Record every imported source and license in `ATTRIBUTION.md`.
- Use a coherent asset family and custom presentation rather than an arbitrary
  collage of packs.

## Explicitly rejected directions

- Visual novel or dialogue-box-driven structure.
- A game built primarily around time loops.
- Government conspiracy, institutional rebellion, or secret cure.
- Killing Death or escaping the protagonist's appointed death.
- Enemies as lifespan farms that imply the hero can live forever.
- Digital watch/numeric countdown display.
- Separate conventional player health bar.
- Automatic timed dagger boomerang.
- Unarmed state with no attack.
- Movement copied together with another game's character, audiovisual
  packaging, and combat role; familiar verbs are allowed when they serve this
  chronosword.
- Screen-space damage numbers.
- Full-screen hit teleport/inversion/glitch effect.
- PS1 posterization.
- Generic backrooms/liminal arena.
- RGB/neon cyberpunk treatment.
- Shallow four-state music crossfade presented as the intended score system.

## Prototype acceptance criteria

The next prototype pass succeeds only if:

1. A new player understands that the analog watch is life without reading a
   numeric timer.
2. Taking a wound visibly costs current time and permanently breaks capacity.
3. Killing an enemy visibly winds the hand back without repairing the rim.
4. Watchfire reads as a physical purple flame and its activation dramatically
   changes hostile motion.
5. Throw, steering, manual rewind, pickup, and unarmed attacks all work.
6. A player can intentionally route the returning dagger through an enemy.
7. Damage numbers rise in the 3D world.
8. The first encounter poses a combat decision rather than a damage race.
9. The space reads as a specific modern-fantasy place, not the backrooms.
10. The browser export starts and the mechanics smoke test passes.
