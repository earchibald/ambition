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

You spawn in the **generated world**: 500 years of history, a nine-chunk surface village, and
its inhabitants standing where the history put them. The debug overlay is on by default.

### Two scenarios

| Scenario | What it is | Boot cost |
|---|---|---|
| `world` (default) | The real thing. DAG history, generated village, factions at their anchors, Pre-Warm. | ~22 ms |
| `test_arena` | The Sprint 1 hand-authored room: ledge, pit, doorway, diagonal pinch, puddle, one rat, one nugget. | ~2 ms |

Switch with `"boot_scenario": "test_arena"` in `debug_config.json`. **Use the arena while
iterating on movement and combat** — it is the loop you pay ~50 times a day, and it is the only
place the specific test features in §3 exist.

### Controls

| Key | Action | What it does in the ECS |
|---|---|---|
| `W` `A` `S` `D` | Move — **7 m/s**, body-relative | `W` walks along the direction you FACE; `A`/`D` strafe across it. Facing comes from the mouse cursor, so the mouse steers and WASD drives. Pushes a `MOVE` **intent**; pressing W does not move you, the ECS decides what W means. |
| `Shift` + move | **Precision** — 35% speed | For lining up on a ledge edge or a pit lip without overshooting. Full speed is for covering ground. |
| `Left mouse` | Attack | You swing **where you point**. The aim vector runs from you to the tile under the cursor; `PickSystem.melee_target` then takes the nearest living entity inside a 2.0 m reach and a 120° arc around it. |
| `Right mouse` | (reserved) | Mapped as `attack_secondary` and reported in the overlay; no behaviour bound yet. |
| `E` | **Use stairs**, or interact / take | Takes what is under the cursor, or the nearest thing within 2.5 m **of you**. Takes a **handful** off a pile too big to carry whole; refuses only when not one unit fits, and then says how many litres are free. |
| `Tab` | Inspect | Selects the entity under the **mouse cursor** and appends its full component dump to the overlay. Falls back to the player if the cursor hits nothing. **Does not toggle off** — see the NOT-built list. |
| `T` | Bullet time | Sets `GameLoopManager.time_scale` to 0.2. Scales delta only — the 60 Hz tick rate never changes (ADR-9). |
| `K` | **DEBUG: injure yourself** — 25 damage | The only way to reach death in the generated world, which has no pit, no hazard and nothing hostile. Four presses kills you. |
| `R` | **DEBUG: run the year and respawn** | Only works once dead. Runs the Interregnum and brings in the successor, so the loop can be completed rather than pausing forever. |
| `F1` | **Cycle overlay page / hide** | LIVE -> CHRONICLE -> FACTIONS -> MAP -> hidden -> LIVE. See below. |
| Drag the header | **Move the debug panel** | Grab the `☰ debug — drag me` bar. Clicks on the panel stay on the panel; they do not swing a weapon at the world behind it. |
| `G` | Toggle debug gizmos | Wireframe facing arrow, melee arc, interact radius, sight radius. On by default. |
| `=` / `-` | Overlay text bigger / smaller | Pure UI. Saved immediately, so it survives a restart. |
| `Esc` | Cancel | Mapped, not yet consumed. |

**The mouse is your steering.** The character turns to face the cursor — watch the yellow nose —
and `W` follows that heading wherever it points. `A` and `D` strafe perpendicular to it, so you
can circle a target while still facing it. The camera itself never rotates.

The camera is a fixed-orientation third-person rig with a **deadzone**:
it does not move at all while you stay within 5 m of its focus point, and outside that it moves
exactly far enough to put you back on the boundary. It never smooths and never rotates.

### The reasoner, and why it needs no API key

ADR-5 was amended: **the LLM is an optional layer.** The shipped default reasons from real
faction state with no network — starvation outranks everything, a recent attack outranks
opportunity, and a raid needs a target it can actually beat. That path runs in CI on every
commit, so it cannot rot.

Watch it work: wait about ten real seconds for a Macro tick, and the event feed prints
`faction 3 -> GATHER_RESOURCES: "Quiet season. Work the stone and the fields."`

To use a real model instead, set both:

```bash
export DELVE_LLM_ENDPOINT="https://api.openai.com/v1"
export DELVE_LLM_API_KEY="sk-..."      # or put it in user://llm_secrets.cfg
export DELVE_LLM_MODEL="gpt-4o-mini"   # optional
```

If the endpoint is set but no key is found, the remote provider is **refused** rather than
half-configured. One that fails every call is worse than none: it burns the queue and hides the
working path. The key is never logged — the overlay reports endpoint and model only.

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

## 3a. What to test right now — CURRENT AS OF SPRINT 3

> **Maintenance rule.** This section is rewritten at the end of every sprint, before its PR
> opens. A play-tester should never have to work out what is finished by poking at it, and three
> stale "what's missing" lists scattered through this file is how that happens. One section, one
> place, updated in step with the code.

### Playable today, by sprint

| Sprint | What it added that you can actually see |
|---|---|
| 1 | Movement, wall sliding, step-up, falling, melee, pickup, the fluid CA, the debug overlay |
| 2 | A generated world: 500 years of history, a nine-chunk village, factions placed by that history |
| 3 | **Villagers walk** planned routes. **Factions decide and speak** once an in-game hour. **Death is a loop** — corpse, loot spill, control detached. **Stairs** to five dungeon floors |
| 3.5 | **Crime has consequences.** Witnesses, grievances, per-faction reputation, gossip that spreads over time, and factions that change what they do because of what you did |

### Inspecting the generated world (`F1`)

The history, the factions and the chunk layout are the whole output of Sprint 2, and until now
none of it was visible. Faction ledgers deliberately have **no position** — they are not objects
in the world — so `Tab` can never reach them, because picking resolves through the spatial hash.

Press `F1` to cycle the pages. A **fifth press dismisses the panel** entirely:

| Page | What it answers |
|---|---|
| **LIVE** | The counters. What the engine is doing right now |
| **CHRONICLE** | The 500 years that produced this world — who was founded, who conquered whom, in which year |
| **FACTIONS** | Every living faction: population (abstract vs embodied), culture, current objective and mood, wealth, home chunk, **how they feel about you and why**, and the last thing they said |
| **MAP** | A **drawn** chunk map of your floor: green active, blue simulated, grey generated, near-black unexplored, with your position, faction anchors and the stairwell marked. Colour-coded legend below it |

Two readings that look wrong and are not:

- **`pop 121 abstract / 0 embodied`** — that faction lives on a floor you have never visited, so
  it exists only as integers. Bodies appear when its chunk is promoted. That is the LoD design.
- **`wealth 1155 units, materialized as stacks`** — an Active faction's ledger is *empty*,
  because promotion spent it into physical piles. The inspector reports the total from whichever
  side currently holds it, so a village you are standing in never reads as destitute.

### The Sprint 3 checks

Boot the `world` scenario (the default) and watch the overlay:

| Check | How | What it proves |
|---|---|---|
| The village walks | Watch `movers` climb above zero, and `paths_requested` tick as they re-plan | Grid A*, the job planner, and the locomotion tiers |
| You can go underground | Walk to tile (34, 32), press `E`. The map title reads `FLOOR -1` | Floor transitions, lazy dungeon generation, and the floor-filtered spatial query |
| Crime has consequences | Kill a villager in view of another. The feed prints the hostility turn; `F1` FACTIONS shows `toward you` going red with the grievance listed | The full chain: combat reports, perception decides who saw, reputation records, gossip spreads, the reasoner reacts |
| Villagers notice you | Stand near one. `perceived (N total)` climbs; Tab it and awareness reads `SUSPICIOUS(1)` | Sight cones, LoS marching, and awareness tiering |
| They avoid walls | Watch a villager cross the village without clipping a building | Active movers are collided by the same system that moves you |
| Factions think | Wait ~10 real seconds for a Macro tick. The feed prints `faction N -> OBJECTIVE: "..."` | The reasoner, the queue, and the validation gate |
| It thinks with no API key | You did not set one. It still decides | ADR-5 as amended: the LLM is optional, and this is the shipped default |
| Death is a loop | Press `K` four times. Control detaches, a corpse appears holding your gear. Then `R` | The handle discipline, the Interregnum taxes, and the Lineage Journal end to end |
| The world has a history | `F1` to CHRONICLE. Read who conquered whom | The DAG really generated 500 years, and the factions you see came from it |
| Factions are real places | `F1` to FACTIONS, then MAP. Anchors match the map | Spatial anchors: nobody spawned at the origin by accident |

### Still worth checking from earlier sprints

| Check | How |
|---|---|
| The village is a real place | Walk across a chunk seam. Sprint 1's collision would have stopped you dead at the boundary |
| It is the same world twice | Note the building layout, restart, compare. Chunks are a pure function of (seed, chunk_id) |
| Villagers are people | **Tall and green.** Monsters are **small and red**, corpses are **flat grey slabs**. Villagers have 100 HP, so killing one takes about three hits |

**For movement feel, combat, fall damage and fluids, use `test_arena`.** Those features have
authored test geometry there and none of it exists in a generated village. Set
`"boot_scenario": "test_arena"` in `debug_config.json`.

### Claims in this file are checked against the code

Every capability above was verified against the implementation before being written down, and the
audit removed two claims that were not true:

- *"Take fatal damage"* was listed as a Sprint 3 check while the generated world contained **no
  pit, no hazard and nothing hostile**. There was no way to reach the death loop at all, and no
  way to leave it once reached, because the Interregnum had no keyboard trigger. `K` and `R` now
  exist for exactly that reason.
- *"Hit a villager and it becomes a slab"* implied one hit. Villagers have 100 HP and a melee
  swing does roughly 35, so it takes about three.

If something here does not work as described, that is a bug in the code or in this file — report
it either way.

### NOT built yet — as of Sprint 3

Not bugs. Listed so play-testing stops rediscovering them:

- **No guards, no arrest, no combat response.** A faction that hates you will FORTIFY and hold a
  grudge, but nobody comes after you. Hostile action against the player is Sprint 4 and later.
- **No respawn UI.** `R` triggers the Interregnum from the keyboard, and it works, but there is
  no fade, no "One Year Passes" card, and no death screen — you simply have control again.
- **Nothing in the world can kill you.** No hazards, no hostile creatures outside the arena. `K`
  exists so the death loop is reachable; a real threat is Sprint 4 and later.

- **No loot placement.** Faction stockpiles materialize at anchors; nothing else is scattered.
- **The doorway is a gap, not a door.** No door entities or openable fixtures exist.
- **No ceilings.** Floors are 2.5D planes (ADR-3), so "indoors" is not a concept the renderer
  expresses yet.
- **No inventory screen.** A successful `E` reports in the event feed and nowhere else.
- **`Tab` does not toggle.** It selects; it never deselects. Pressing it on empty ground falls
  back to inspecting you rather than clearing, so once the inspection panel is up there is no way
  to get the unobstructed LIVE view back short of cycling `F1` off and on. Fixed first thing in
  Sprint 4 (roadmap Step 5).

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

Colour is reserved for values measured against a threshold, so it always carries information:
**green** inside budget, **amber** approaching it, **red** over — or, for `handles`, red the
moment a stale rejection appears, since that counter should never be anything but zero.



```
Spring 1 06:00  |  scenario world  |  60 fps (16.7 ms/frame)
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
| the pit at (40-45, 12-17) | `vitals:` flips to `FALLING x.x m/s`, then the feed reports the landing. See the note below — this is a **small** hit by design |
| the ramp at (46-51, 14-15) | You climb back out of the pit, 0.4 m per tread |
| the diagonal pinch at (50, 20)/(51, 21) | You do **not** slip through the shared corner |
| the puddle at (10, 10) | `fluid` drops in the cell you displace, and `CA updates` rises |

`Tab` adds the selected entity's tile to the inspector block as well.

### Why the 2.5 m pit barely hurts

Measured, walking east off the rim: **lands at 5.40 m/s for 1.82 damage out of 100.**

That is not a broken fall, it is three rules composing:

* `AUTO_DROP_MAX_M` is 1.0 m, so the last metre is *snapped*, not fallen. A 2.5 m pit is only a
  1.5 m free fall.
* 1.5 m of free fall reaches 5.40 m/s.
* `SAFE_FALL_MPS` is 5.0, so only the 0.40 m/s of excess does any damage at all.

Anything under a **2.3 m** total drop is therefore completely free. The pit sits just past that
line on purpose, so it demonstrates that the threshold exists.

Be aware the curve past the threshold is **steep**: damage is `0.5·m·(v−5)²/J_PER_HP`, which for
a 70 kg body is `11.7·(v−5)²`. A 4 m pit would deal ~83 damage and a 5 m pit would be fatal. If
falls should be more survivable, the dial is `J_PER_HP` (currently 3.0), not the pit depth.

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

### One arena quirk worth knowing

**The arena rat does not move or notice you.** It has Needs, Schedule, Perception and Memory, but
the arena has no faction to plan for it, so nothing assigns it a destination. `perceived 0
witnesses 0` on a bare arena boot is expected. Its awareness reads `UNAWARE(0)` — that is
*unaware*, not asleep; there is no sleep state.

Villagers in the `world` scenario do move, because a faction plans for them (Sprint 3).

The full not-built-yet list lives in §3a, in one place, so it cannot drift out of date in three.

### Going underground

The village's landing chunk — chunk (0, 0) — has a **stairwell**. It is marked in the world by a **cyan beacon column** you can walk toward from
anywhere in the village, and the tile itself is a sunken cyan slab. The cursor readout confirms
`STAIRS (press E)`. Up-stairs are amber and raised.

There are five floors below the surface. Each landing chunk has a way up and, unless it is the
bottom, a way down. You arrive at the OPPOSITE stair from the one you used, which is where you
would be if you had walked down — arriving on the stair you left by would put you on a tile that
sends you straight back.

The `F1` MAP page follows you: `FLOOR -2` in its title, and a fresh grid of chunks generated on
demand as you explore.

Dungeon floors are rooms-and-corridors, not village buildings, and they are **empty** — factions
anchored down there exist as ledgers with no bodies until their chunk is promoted. Watch the
FACTIONS page: `0 embodied` becomes a real number once you stand in their chunk.

### The debug panel

It **scrolls** once its content passes 80% of the window height, so the chronicle and the faction
list are fully readable rather than running off the bottom.

It is a draggable, non-modal window rather than text painted on the corner of the screen. Grab
its header to move it off whatever you are trying to look at. Clicking anywhere on it is
consumed by the panel, so reading the overlay no longer attacks the thing behind it.

The font is **monospace** on purpose: the `F1` map is a grid of characters, and a proportional
font shreds its columns until it stops being a map.

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

Expected: **25 scripts, 307 tests, 307 passing**. Under three seconds.

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
| `test_playtest_regressions.gd` | Every defect a human found by playing that the suite had missed |
| `test_camera_and_motion.gd` | Deadzone arithmetic, fixed-timestep interpolation, the aim sweep |
| `test_dag_history.gd` | Bounded generation, reproducibility, conquest wealth conservation |
| `test_world_generation.gd` | Per-chunk determinism, gate connectivity, the tile sampler, anchors |
| `test_dag_instantiation.gd` | Entity-count discipline: ledgers vs bodies, quantity vs entities |
| `test_lod_conservation.gd` | **Cross a boundary twenty times, total faction value invariant** |
| `test_gray_box_economy.gd` | The off-screen economy creates zero entities, and says so itself |
| `test_bootstrapper.gd` | Boot ORDER, the coarse interregnum, Pre-Warm gravity suppression |
| `test_pathfinding_and_movement.gd` | A* bounds and correctness, both locomotion tiers, the planner |
| `test_reasoning.gd` | The heuristic reasoner, the queue, and every branch of the validation gate |
| `test_death_loop.gd` | Corpse and loot spill, the generation bump, the taxes, the Lineage Journal |
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
| A function silently returns `false` for no reason | A typed array assigned from a ternary throws at RUNTIME and aborts the function mid-way | Build it explicitly. `invariants/test_forbidden_apis.gd` scans for this — it has shipped twice |
| A test asserts nothing but passes | GDScript lambdas capture primitives BY VALUE, so assigning to a captured `bool` never escapes | Collect into an Array or Dictionary; those are references |
| NPCs stand still in `world` | No faction planned for them, or A* found no route | Check `paths_requested` and `path_failures` in the overlay |
