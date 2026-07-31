# Running and Testing The Living Delve

Everything below was executed on macOS with Godot 4.7.1 before it was written down. If a command
here does not work, that is a bug — file it, do not work around it silently.

## 1. Prerequisites

| Tool | Version | Why |
|---|---|---|
| Godot | **4.7.1** exactly | Pinned in `project.godot`, the CI image, and `README.md` §5. Other 4.x versions parse `@abstract` and typed arrays differently. |
| Python 3 + `gdtoolkit==4.5.*` | for linting only | CI installs it; you only need it locally if you want to lint before pushing. |

Install Godot:

```bash
brew install --cask godot          # macOS
godot --version                    # must print 4.7.1
```

GUT (the test framework) is **vendored** in `addons/gut`. There is nothing to install.

## 2. First run — do this once after cloning

The import step is not optional. `class_name` globals and cross-file enums do not resolve until
Godot has imported the project, so a fresh clone fails with `Identifier "X" not declared` on
every single script.

```bash
cd ambition
godot --headless --import
```

## 3. Play it

```bash
godot res://viewer/Main.tscn
```

You spawn in a 64x64 stone arena. The debug overlay is on by default in the top-left.

### Controls

| Key | Action | What it does in the ECS |
|---|---|---|
| `W` `A` `S` `D` | Move | Pushes a `MOVE` **intent** onto entity 0's action queue. Camera-relative on the XZ plane. Pressing W does not move you; the ECS decides what W means. |
| `Left mouse` | Attack | You swing **where you point**. The aim vector runs from you to the tile under the cursor; `PickSystem.melee_target` then takes the nearest living entity inside a 2.0 m reach and a 120° arc around it. |
| `Right mouse` | (reserved) | Mapped as `attack_secondary` and reported in the overlay; no behaviour bound yet. |
| `E` | Interact / take | Takes what is under the cursor, or failing that the nearest thing within 2.5 m **of you**. Reach is measured from the player, never from the camera. |
| `Tab` | Inspect | Selects the entity under the **mouse cursor** and appends its full component dump to the overlay. Falls back to the player if the cursor hits nothing. |
| `T` | Bullet time | Sets `GameLoopManager.time_scale` to 0.2. Scales delta only — the 60 Hz tick rate never changes (ADR-9). |
| `G` | Toggle debug gizmos | Wireframe facing arrow, melee arc, interact radius, sight radius. On by default. |
| `=` / `-` | Overlay text bigger / smaller | Pure UI. Saved immediately, so it survives a restart. |
| `Esc` | Cancel | Mapped, not yet consumed. |

There is no mouse-look. The camera is a fixed-orientation third-person rig with a **deadzone**:
it does not move at all while you stay within 5 m of its focus point, and outside that it moves
exactly far enough to put you back on the boundary. It never smooths and never rotates.

### The debug gizmos (`G`)

The player is a featureless box, so the rules that depend on direction and distance had no
on-screen representation at all. Every radius drawn is **read from the system that enforces it**,
so a gizmo cannot disagree with the rule it depicts:

| Gizmo | Colour | Source of truth |
|---|---|---|
| Facing arrow | yellow | The live aim vector, recomputed each frame from your cursor |
| The player's **nose** | yellow, on the body | Same aim vector. Drawn on the character itself, not just the floor, so heading is readable with gizmos off |
| Melee wedge | red | `PickSystem.MELEE_REACH_M` (2.0 m) and the ±60° arc test |
| Interact ring | cyan | `PickSystem.INTERACT_DIST_M` (2.5 m) |
| Sight ring | violet | `PerceptionComponent.sight_range_m` (12 m), drawn only if the entity has the component |

The wedge is what you aim; if a target is not inside it, the swing will be refused and the event
feed will say so.

Aim rotates **continuously** everywhere, including behind you and above the horizon. A camera ray
that never meets the ground keeps the heading the cursor implies, which is exactly the limit the
ground intersection approaches as the ray flattens — so the two cases meet without a seam.

### What is in the arena, and what each thing is there to test

The arena is hand-authored in `ecs/world/test_arena.gd`. Every feature exists to exercise one
rule, so "walking around" is a real test pass:

| Where | Feature | Rule under test |
|---|---|---|
| Spawn, tile (8, 32) | You, the cyan box | — |
| ~3 m east | A **red** box: a corpse rat, 8 HP | Melee, the energy damage model, the gib threshold |
| ~1.5 m east | A **gold** box: 5 copper nuggets | `TAKE` intent, the loose-item integrator, inventory volume |
| Tile x=24, full height | Interior wall with a 2-tile doorway at y=32-33 | Wall sliding, and line-of-sight occlusion |
| Tiles (40-49, 40-49) | Ledge raised 0.4 m | The step-up rule — you should climb it without jumping |
| Tiles (40-45, 12-17) | Pit, 2.5 m deep | Drop handling and fall damage |
| Tiles (50, 20) / (51, 21) | Two diagonally touching walls | The vertex-squeeze case: an axis-separated resolve would let you slip through the shared corner |
| Tile (10, 10) | Blue puddle | The fluid cellular automaton |

### Reading the debug overlay

```
Spring 1 06:00  |  scenario test_arena
you: tile (8, 32)   world (8.50, 0.90, 32.50)   open  elev +0.00m  fluid 0
cursor: tile (24, 37)   SOLID  elev +0.00m  fluid 0
vitals: health 100.0/100.0   stamina 99.8   grounded   (safe fall < 5 m/s)
mouse: LMB up  RMB up   attack-presses 0  interact-presses 0
micro 0.53ms / 8.0ms budget   sim 0.02ms   fluid 0.00ms   spatial 0.49ms
entities alive 3 (active 3 / cap 3000)   rows 3   free 0
movers 1  substeps 6  tile-hits 0  entity-hits 0
CA updates 0  dirty 0   pumped 0
LoS marches 0 (cache 0, fail 0)  perceived 0  witnesses 0
stale-handle rejections 0   destroys 0   query rebuilds 13
```

### Checking your position against the arena table

The `you:` line is how you verify anything in the table above. Every arena feature is authored in
**tile** coordinates, but the ECS stores **metres**, so the overlay prints both:

* `tile (8, 32)` — grid coordinate. This is what the table in §3 uses. On boot it is
  `TestArena.SPAWN_TILE`, and a test asserts those two agree.
* `world (8.50, 0.90, 32.50)` — metres. Tiles are 1 m and the reported point is the tile centre,
  so world X and Z are always tile + 0.5. Y is the entity centre, which for the player sits
  0.9 m above the floor (half of its 1.8 m height).
* `open` / `SOLID`, `elev`, `fluid` — the three tile facts the simulation actually reads.
  `elev` is the number the step-up and drop rules compare; `fluid` is what the CA moves.

There are **two separate questions**, and each has its own tool. Do not confuse them.

**"Is the map what the spec says?"** — use the cursor. No walking. Point the mouse at any tile on
screen and read the `cursor:` line. The ray is marched against the real height map, so it is
correct on the ledge and in the pit too, not just on flat ground.

| Point the cursor at | Expect |
|---|---|
| tile x=24, any y except 32-33 | `SOLID` |
| tile (24, 32) or (24, 33) | `open` — the doorway |
| tiles (40-49, 40-49) | `elev +0.40m` — the ledge |
| tiles (40-45, 12-17) | `elev -2.50m` — the pit |
| tile (10, 10) | `fluid` above zero — the puddle |

**"Do the movement rules work?"** — this one needs walking, because the rules are about what
happens when a body moves into a tile. The cursor cannot answer it: it reads terrain, not
collision. Watch the `you:` line as you go.

| Walk into | Expect |
|---|---|
| the wall at x=24 | You stop, and slide along it rather than sticking |
| the doorway at (24, 32-33) | You pass through |
| the ledge at (40-49, 40-49) | You **step up** without jumping, and `you:` reports `elev +0.40m` |
| the pit at (40-45, 12-17) | `vitals:` flips to `FALLING x.x m/s`, then the event feed reports the damage. A 2.5 m drop lands at ~5.4 m/s, just past the 5 m/s safe limit, so expect a small hit rather than a large one |
| the diagonal pinch at (50, 20)/(51, 21) | You do **not** slip through the shared corner |
| the puddle at (10, 10) | `fluid` drops in the cell you displace, and `CA updates` rises |

`Tab` adds the selected entity's tile to the inspector block as well.

### The event feed

The last eight outcome events appear at the bottom, newest first, stamped with the in-game clock:

```
recent events (newest first):
  Spring 1 06:00  creature #1 took 3.4 damage (melee), 4.6 left
  Spring 1 06:00  you: attack refused — nothing in reach
  Spring 1 06:00  you took 1.2 damage (fall), 98.8 left
```

This is how you tell a miss from a hit, and a step from a fall. **Refusals are reported too** —
if an action does nothing, the feed says why rather than leaving you guessing.

### Things that are deliberately missing in Sprint 1

Not bugs, just not built yet. Listed so play-testing does not keep rediscovering them:

* **The doorway is a gap, not a door.** There are no door entities, hinges, or openable fixtures.
  Every opening in the arena is simply an absence of wall.
* **The rat does not move or notice you.** It has Needs, Schedule, Perception and Memory, but no
  job source and no Simulated-tier movement, so `perceived 0  witnesses 0` on a bare boot is
  expected. NPC movement lands in Sprint 2. Its awareness reads `UNAWARE(0)` — that is *unaware*,
  not asleep; Sprint 1 has no sleep state at all.
* **There is no ceiling and no roof.** Floors are 2.5D planes (ADR-3), so "indoors" is not yet a
  concept the renderer expresses.
* **No inventory screen.** A successful `E` reports in the event feed and nowhere else.

### If the text is too small

The overlay defaults to 20 pt at a 1280x720 reference and scales with the window, since the
project uses `canvas_items` stretch. To change it:

* Press `=` to enlarge and `-` to shrink, at any time. The choice is saved immediately and
  survives a restart.
* Or set `"overlay_font_size"` in `debug_config.json` (see the path below). Range is 10 to 64.

The two lines worth watching:

* **`micro ... / 8.0ms budget`** appends `<< OVER` when the Micro tick misses ADR-10's budget.
  With 3 entities it will not. See §6 — it does at 1,500.
* **`stale-handle rejections`** counts lookups against destroyed entities. Any number above zero
  after a normal session means something is holding a handle past its generation bump.

`CA updates 0  dirty 0` is correct once the puddle has settled — a settled cell leaves the dirty
set, which is the whole point of the hysteresis. Break the puddle by walking into it and the
count rises again.

To change what is drawn, write `debug_config.json` into the user data directory
(`~/Library/Application Support/Godot/app_userdata/The Living Delve/` on macOS):

```json
{ "tick_counters_enabled": true, "fluid_overlay_enabled": true, "event_trace_enabled": true }
```

## 4. Run the tests

The full suite, exactly as CI runs it:

```bash
godot --headless -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests \
  -ginclude_subdirs \
  -gexit
```

`-ginclude_subdirs` is **required**, not optional. GUT's `-gdir` does not recurse, so without it
`tests/invariants/`, `tests/perf/` and `tests/soak/` are silently skipped and the run reports
green having never opened them.

Expected: **14 scripts, 141 tests, 141 passing, ~7,480 asserts**, in about 1.5 seconds.

One file at a time, which is what you want while iterating:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_fluid_dynamics.gd -gexit
```

### What each suite covers

| File | Covers |
|---|---|
| `test_entity_handle.gd` | Packed 64-bit handles, generation bumps, JSON round-tripping (ADR-19, ADR-21) |
| `test_ecs_lifecycle.gd` | Row allocation, atomic destroy, the `query(mask)` façade, stale-handle rejection |
| `test_sprint0_gate.gd` | Autoloads, InputMap, tick cadences, main scene — the Sprint 0 gate as assertions |
| `test_collision_and_spatial.gd` | Swept AABB, substepping, axis order, diagonal squeeze, step/drop, the spatial hash |
| `test_fluid_dynamics.gd` | Volume conservation, settling, the ghost apron, LoD round trips, budget deferral |
| `test_combat_math.gd` | Kinetic energy, the gib threshold, damage floors |
| `test_perception.gd` | Awareness tiers, symmetric LoS caching, hearing attenuation, witness events |
| `test_material_and_thermo.gd` | Volume fractions, mass, the enthalpy model, the equilibrium clamp |
| `test_behaviour.gd` | Utility scoring, hysteresis, the job latch, need-driven preemption |
| `test_inventory_and_lod.gd` | Container volume, LoD transitions, conservation across them |
| `test_viewer_visibility.gd` | That you can actually **see** it — see §5 |
| `invariants/test_forbidden_apis.gd` | The Prime Directive: no physics nodes; `ecs/` never reads wall-clock |
| `perf/test_micro_tick_benchmark.gd` | The ADR-10 budgets, as numbers — see §6 |
| `soak/test_soak_invariants.gd` | Long-run conservation and leak checks |

### Lint

```bash
pip3 install --break-system-packages "gdtoolkit==4.5.*"
for d in ecs singletons ui viewer tests; do gdlint "$d"; done
```

Never lint `addons/` — GUT is third-party and is not gdlint-clean.

## 5. Verifying it actually renders

Headless green proves nothing about the screen. Sprint 1 passed 135 tests while rendering an
empty grey void: nothing in `viewer/` read the tile map, and the player was never announced to
`ViewManager`, so there was no floor, no walls, and no player body. `test_viewer_visibility.gd`
exists so that cannot silently recur.

To capture actual frames without a display session:

```bash
mkdir -p /tmp/frames
godot --write-movie /tmp/frames/f.png --fixed-fps 10 --quit-after 40 \
      --resolution 1280x720 res://viewer/Main.tscn
```

Godot's movie writer emits a PNG per frame. Open the last one. You should see a grey stone floor,
dark walls, a cyan player box, a red rat, a gold nugget, a blue puddle, and the overlay.

## 6. Performance

The benchmark is a test, not a script, so the budgets fail CI rather than sitting in a wiki:

```bash
godot --headless -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/perf/test_micro_tick_benchmark.gd -gexit
```

Measured on an M5 Max **debug** build:

```
PERF  entities=   50  micro(collision+hash)= 0.875 ms  budget=8.0 ms  ok
PERF  entities=  500  micro(collision+hash)= 4.831 ms  budget=8.0 ms  ok
PERF  entities= 1500  micro(collision+hash)=13.661 ms  budget=8.0 ms  OVER
PERF  CA cells= 3844   3.194 ms  0.831 us/cell  -> 20k cells would cost 16.6 ms
PERF  spatial hash rebuild, 1500 entities = 1.014 ms
```

**Sprint 1 does not meet the ADR-10 Micro budget at the 1,500-entity target.** Scaling is linear;
the constant is too high. Do not "fix" this by lowering the entity cap. The agreed response is to
port the CA and the spatial hash to Rust/GDExtension. See `STATE.md`.

## 7. Git workflow

`main` is stable, `dev` is integration, and you branch off `dev`:

```bash
git checkout dev && git pull
git checkout -b feature/my-thing
# ... work ...
gh pr create --base dev
```

Never push to `main`. Never merge your own PR without human review. CI runs lint, import, a boot
smoke test, and the full GUT suite on every PR into `dev` or `main`.

## 8. When something goes wrong

| Symptom | Cause | Fix |
|---|---|---|
| `Identifier "X" not declared` on every script | Project never imported | `godot --headless --import` |
| Tests pass but you know they should not | `-ginclude_subdirs` missing, so subdirectories were skipped | Add the flag; check the reported script count is 14 |
| Boot exits 0 but nothing works | A `_ready()` runtime error still exits 0 | Grep the output for `ECS_BOOT_OK`; its absence is the failure signal |
| Grey void, no floor or walls | `TerrainView` missing from `Main.tscn` | Run `test_viewer_visibility.gd` |
| Player invisible | `World._spawn_player` did not emit `entity_created` | Same test |
| `Input.get_vector()` errors every frame | An action is missing from the InputMap | `test_sprint0_gate.gd` lists every required action |
