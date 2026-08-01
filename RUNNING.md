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

**Switch with a command-line flag.** No file to find, no JSON to edit:

```bash
godot --scenario=test_arena res://viewer/Main.tscn
godot --scenario=world      res://viewer/Main.tscn
```

Every boot prints which one it chose and where the config file is, so this is never a guess:

```
scenario: test_arena   (override: --scenario=test_arena|world)
debug config: /Users/you/Library/Application Support/Godot/app_userdata/The Living Delve/debug_config.json
```

The flag applies to **that run only** and is deliberately never written back — otherwise one
`--scenario=test_arena` would silently make the debug room your permanent default.

To change the default instead, edit `boot_scenario` in that file. It lives under Godot's user
data directory, which is OS-specific and not guessable:

| OS | Path |
|---|---|
| macOS | `~/Library/Application Support/Godot/app_userdata/The Living Delve/debug_config.json` |
| Linux | `~/.local/share/godot/app_userdata/The Living Delve/debug_config.json` |
| Windows | `%APPDATA%\Godot\app_userdata\The Living Delve\debug_config.json` |

It may not exist yet — the game writes it the first time you change the overlay text size with
`=`/`-`. Creating it by hand with just `{ "boot_scenario": "test_arena" }` also works; every
other key falls back to its default.

**Use the arena while iterating on movement and combat** — it is the loop you pay ~50 times a
day, and it is the only place the specific test features in §3 exist.

### Controls

| Key | Action | What it does in the ECS |
|---|---|---|
| `W` `A` `S` `D` | Move — **7 m/s**, body-relative | `W` walks along the direction you FACE; `A`/`D` strafe across it. Facing comes from the mouse cursor, so the mouse steers and WASD drives. Pushes a `MOVE` **intent**; pressing W does not move you, the ECS decides what W means. |
| `Shift` + move | **Precision** — 35% speed | For lining up on a ledge edge or a pit lip without overshooting. Full speed is for covering ground. |
| `Left mouse` | Attack | You swing **where you point**. The aim vector runs from you to the tile under the cursor; `PickSystem.melee_target` then takes the nearest living entity inside a 2.0 m reach and a 120° arc around it. |
| `Right mouse` | (reserved) | Mapped as `attack_secondary` and reported in the overlay; no behaviour bound yet. |
| `B` | **Grimoire** — compose a spell | Opens the rune list. `1`-`9` add and remove runes, `Enter` binds, `Backspace` clears, `B` or `Esc` closes. The panel previews the compiled spell live — cost, radius, lifetime, and any cap that fired — and previewing costs nothing. |
| `Q` | **Cast** the bound spell | Fires whatever the Grimoire last bound, aimed where the cursor points. Refuses out loud if nothing is bound, or if you lack the stamina. Magic costs **stamina**, not mana. |
| `H` | **DEBUG: fill the chunk with spores** | Toggles. The only route to the mutation loop — no hazard zone occurs naturally in either scenario yet. About 50 s of standing in it produces a mutation. |
| `E` | **Use stairs**, or interact / take | Takes what is under the cursor, or the nearest thing within 2.5 m **of you**. Takes a **handful** off a pile too big to carry whole; refuses only when not one unit fits, and then says how many litres are free. |
| `Tab` | Inspect — **toggles** | Selects the entity under the **mouse cursor** and appends its full component dump to the overlay. Tab the **same** target again to clear it; Tab **empty ground** to clear it. Tab a **different** target to switch straight to it, with no clearing press in between. |
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

## 3a. What to test right now — CURRENT AS OF SPRINT 4

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
| 4 | **Magic you compose yourself** (`B` to build a spell, `Q` to cast it). **Chemistry that chains** — fire spreads, gas explodes, water quenches. **Your body changes** in a hazardous place, and factions judge you for it by their own culture |

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

### The Sprint 4 checks

**Use `test_arena` for these** — `godot --scenario=test_arena res://viewer/Main.tscn`, or see §3
for the config-file route. The generated village has no spores, no volatile gas and nothing
burning; the arena is where the Sprint 4 props are placed. They sit apart from each other on purpose, so nothing goes off before
you do it.

Where they are, relative to your spawn point:

| Prop | Offset from spawn | What it is for |
|---|---|---|
| Spore cloud | 8 m **ahead** (+Z) | Shoot it: flash-fire |
| Volatile gas | 8 m ahead, 6 m **right** | Shoot it: explosion |
| Brazier | 4 m ahead, 4 m **left** | Already alight. Fuel for `Absorb_Heat`, and a fire for water to quench |

| Check | How | What it proves |
|---|---|---|
| **You can build a spell** | `B`. Press the numbers for `On_Cast`, `On_Impact`, `Projectile`, `Add_Temperature`, `Apply_Burning`. The panel prints the compiled line — `r1.5m v18 ttl3.0s strain 20.0 +Burning` — as you go | The compiler, and the Dry Run: this preview is the same pure code a real Bind runs, and it costs nothing |
| **The cognitive cap refuses** | Keep adding runes past a total cost of 15. The preview turns red: `will not compile — exceeds cognitive limits` | The complexity gate. Your budget is `Rune_Stability x 1.5`, and a starting adventurer has 10 |
| **The geometric cap clamps** | It cannot be reached with the starting runes — the over-sized ones are not in your grimoire yet. `tests/test_spellcraft.gd` covers it | The two caps fail **differently** on purpose: complexity refuses, geometry overrides and tells you it did |
| **Casting costs you** | `Enter` to bind, then `Q`. Watch the stamina bar drop by the strain figure | Magic has no mana bar. It is paid for out of the body |
| **A miss still expires** | Cast at open floor. `magic` shows `1 in flight`, then it goes off at the end of its range | The TTL sweep. An ephemeral that never expires is a leak with a radius |
| **The flash-fire** | Aim at the spore cloud, `Q`. It catches; `chemistry` shows a reaction; the room's `air` figure climbs | The reaction matrix, and energy derived from what is burning rather than typed into a table |
| **The explosion** | Aim at the volatile gas instead. It is consumed, and the rat is thrown clear | The same matrix, a different rule, a visibly different outcome |
| **It cannot loop** | Watch `chemistry` after a reaction: `locked` is non-zero for 60 frames. Tab a participant — its tags read `Reaction_Cooldown(43f)` | The anti-recursion lock, counting down where you can see it |
| **Your body changes** | `H`, then stand still for about a minute. Tab yourself: `exposure: FUNGAL 62%` climbs, then the feed prints `you MUTATED — Fungal_Lungs` | The ecology loop. Exposure, the threshold, and a permanent change |
| **The mutation is a trade** | After it lands, your **stamina bar is shorter** — max stamina fell by 20 — and you now resist spores | Every mutation costs something, or a hazard is a farm |
| **Factions judge you by their own culture** | With a mutation, walk into view of a villager. `F1` FACTIONS: a Farming/Trade culture moves **against** you, a Raiding/Scavenging one moves **toward** you | The mutation shift is gossip-propagated reputation, not a hivemind — and it is the only act in the game whose severity depends on who saw it |
| **Tab toggles** | Tab a villager, read the panel, Tab the same villager again — the panel goes. Tab a second villager directly and it switches without a clearing press | Sprint 4 Step 5, the playability defect carried over from Sprint 3 |

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
authored test geometry there and none of it exists in a generated village:
`godot --scenario=test_arena res://viewer/Main.tscn`.

### Claims in this file are checked against the code

Every capability above was verified against the implementation before being written down, and
`tests/test_grimoire_ui.gd` runs the two Sprint 4 demos end to end — bind a fireball, shoot the
spore cloud, watch the room warm — so if those instructions go stale the suite goes red. That is
deliberate: this file is a contract, and a contract nothing checks is a wish.

Corrections earlier audits forced, kept as a record of the failure mode:

- *"Take fatal damage"* was listed as a Sprint 3 check while the generated world contained **no
  pit, no hazard and nothing hostile**. There was no way to reach the death loop at all, and no
  way to leave it once reached, because the Interregnum had no keyboard trigger. `K` and `R` now
  exist for exactly that reason — and `H` was added in Sprint 4 before the same thing could
  happen to mutation.
- *"Hit a villager and it becomes a slab"* implied one hit. Villagers have 100 HP and a melee
  swing does roughly 35, so it takes about three.

If something here does not work as described, that is a bug in the code or in this file — report
it either way.

### NOT built yet — as of Sprint 4

**ONE list, rewritten every sprint, never appended to.** Not bugs. Listed so play-testing stops
rediscovering them.

**World and threat**

- **No guards, no arrest, no combat response.** A faction that hates you will FORTIFY and hold a
  grudge, but nobody comes after you.
- **Nothing in the world attacks you.** No hostile creatures outside the arena, and no naturally
  occurring hazard zones — which is why `K` exists to reach death and `H` exists to reach
  mutation. Both are debug keys standing in for content.
- **No loot placement.** Faction stockpiles materialize at anchors; nothing else is scattered.
- **The doorway is a gap, not a door.** No door entities or openable fixtures exist.
- **No ceilings.** Floors are 2.5D planes (ADR-3), so "indoors" is not a concept the renderer
  expresses yet.

**Magic**

- **The Grimoire is a keyboard list, not the node graph.** The drag-and-drop editor, the Dry Run
  **hologram** (a 3D wireframe preview in a SubViewport) and the translation-cipher minigame from
  `inventory_and_grimoire_mechanics_specification.md` §2 are a UI sprint. The Dry Run's *logic*
  is built — the panel previews the real compiled spell — but it is text, not wireframes.
- **No overclocking and no mishap table.** A spell you cannot afford is refused; it cannot be
  force-compiled into an `[Unstable]` one that rolls d100 on cast. Spec'd in the grimoire doc,
  not built.
- **You cannot learn new runes in play.** `MindComponent.known_runes` is seeded with seven and
  nothing in the world grants more. The ruined libraries the DAG places are not readable yet, so
  the runes that exist to be excavated — `Great_Aura`, `Heavy_Projectile`, `On_Proximity`,
  `On_Timer`, `Cone`, `Apply_Filth`, `Apply_Spores`, `Absorb_Heat`, `Chill`, `Remove_Wet` — are
  reachable only from tests.
- **Spells have no visual.** A cast spawns a real entity that moves, collides and applies its
  payload, and `ViewManager` draws it as an ordinary box. No particles, no light, no trail.
- **NPCs do not cast.** The compiler is reachable by any mind; only the player's is driven.

**Chemistry**

- **Four reaction rules**, not a content library: fire+gas, fire+spores, fire+water, and the
  self-quench. Enough to prove the matrix; not a game's worth of chemistry.
- **Heat does not ignite.** There is no ignition-temperature model, so `Add_Temperature` alone
  will not set a flammable thing alight — a spell has to say `Apply_Burning`.
- **Gas is temperature-driven only.** A material becomes gaseous when the chunk's ambient passes
  its boiling point. There is no separate gas emission, no pressure, and no ventilation.

**Body and interface**

- **Four mutations, one per hazard track.** The table is a worked example, not a content set.
- **No respawn UI.** `R` triggers the Interregnum and it works, but there is no fade, no "One
  Year Passes" card, and no death screen — you simply have control again.
- **No inventory screen.** A successful `E` reports in the event feed and nowhere else.

### What is in the arena, and what each thing is there to test

The arena is hand-authored in `ecs/world/test_arena.gd`. Every feature exists to exercise one
rule, so "walking around" is a real test pass:

| Where | Feature | Rule under test |
|---|---|---|
| Spawn, tile (8, 32) | You, the cyan box | — |
| ~3 m east | A **red** box: a corpse rat, 8 HP | Melee, the energy damage model, the gib threshold |
| ~1.5 m east | A **gold** box: 5 copper nuggets | `TAKE` intent, the loose-item integrator, inventory volume |
| 8 m ahead (+Z) | A **spore cloud** — 0.1 kg of biomass tagged `Spores` | The flash-fire rule, combustion energy derived from material, the ambient rise |
| 8 m ahead, 6 m right | A **volatile gas pocket** — sulfur tagged `Volatile_Gas` | The explosion rule, the blast impulse, and `consumes` destroying a reactant |
| 4 m ahead, 4 m left | A **brazier**, already `Burning`, holding 5 MJ | `Absorb_Heat`'s environmental resource, and a fire for water to quench |
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
* Or launch with `--overlay-font=28`. Range is 10 to 64, and like `--scenario` it applies to that
  run only.
* Or set `"overlay_font_size"` in `debug_config.json` (paths in §3) to change the default.

The two lines worth watching:

* **`micro ... / 8.0ms budget`** appends `<< OVER` when the Micro tick misses ADR-10's budget.
  With 3 entities it will not. See §6 — it does at 1,500.
* **`stale-handle rejections`** counts lookups against destroyed entities. Any number above zero
  after a normal session means something is holding a handle past its generation bump.

`CA updates 0  dirty 0` is correct once the puddle has settled — a settled cell leaves the dirty
set, which is the whole point of the hysteresis. Break the puddle by walking into it and the
count rises again.

To change what is drawn, write `debug_config.json` into the user data directory (paths in §3;
the game prints the exact one at every boot):

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

Expected: **32 scripts, 506 tests, 506 passing**. Under six seconds.

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
| `test_playtest_regressions.gd` | Every defect a human found by playing that the suite had missed, including the `Tab` toggle |
| `test_reactions.gd` | The reaction matrix: sorted-pair keys, INTRA/INTER/BOTH scope, the anti-recursion lock and its expiry, derived combustion energy, the ambient rise and its cap, the blast, and gas in the fluid grid |
| `test_spellcraft.gd` | The compiler (both caps, and that they fail differently), trigger precedence, the cone wedge, casting, strain, projectile/aura/timer/proximity behaviour, and `Absorb_Tag` conservation including the double-spend |
| `test_mutation.gd` | Exposure, the threshold and its unconditional reset, the mutation table's real stat effects, resistance, culture-dependent severity, and that mutations reset on death while insight carries |
| `test_grimoire_ui.gd` | The **route in**: key press to intent to spell in the world, plus the two demos this file tells you to run |
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

Measured on an M5 Max **debug** build, Sprint 4:

```
PERF  entities=   50  micro(collision+hash)= 1.279 ms  budget=8.0 ms  ok
PERF  entities=  500  micro(collision+hash)= 7.926 ms  budget=8.0 ms  ok
PERF  entities= 1500  micro(collision+hash)=22.978 ms  budget=8.0 ms  OVER
PERF  CA cells= 3844   4.135 ms  1.076 us/cell  -> 20k cells would cost 21.5 ms
PERF  spatial hash rebuild, 1500 entities = 1.149 ms
PERF  reactions, 500 reactive entities = 1.333 ms/tick  budget=8.0 ms  ok
PERF  ephemerals, 200 auras = 0.472 ms/tick
```

**The build does not meet the ADR-10 Micro budget at the 1,500-entity target.** Scaling is
linear; the constant is too high. Do not "fix" this by lowering the entity cap. The agreed
response is to port the CA and the spatial hash to Rust/GDExtension. See `STATE.md`.

Three things about these numbers, because a benchmark that is not read honestly is worse than
none:

- **The collision figures are higher than the Sprint 1 record (13.7 ms at 1,500) and Sprint 4 did
  not cause it.** Measured both ways with `git stash`: 22.3 ms with Sprint 4 and 22.7 ms without.
  It is this machine on this day. The earlier figure was recorded elsewhere and should not be
  compared against directly.
- **Sprint 4 did cost the fluid CA about 10%** — 0.97 to 1.07 us/cell, measured the same way. The
  first version cost **+48%**, because the gas check was a function call per cell inside the
  hottest loop in the build; it is now a table built once per tick with a `_any_gas` early-out
  that a normal 20 C room never indexes.
- **The two new 60 Hz systems are now benchmarked**, because ADR-10's whole lesson is that an
  unmeasured budget is a wrong one. The reaction figure is a worst case: 500 entities, every one
  of them reactive, none on cooldown.

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
