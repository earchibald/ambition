# Scope & Milestones

**Status:** Authoritative scope contract. Created by the 2026-07-31 gestalt review, which found
that 6,700 lines of specification contained no effort estimate, no version boundary, and no cut
list — and that this absence is why the spec set kept growing (three adversarial review
documents exist, one of which reviews the repairs made in response to another).

This document exists to make scope decisions explicit and reviewable. It is deliberately short.

---

## 1. The problem this solves

At the time of writing: 40 spec docs, ~6,700 lines, 2 commits, and zero lines of gameplay code.
Specification is infinitely elastic; code is not. Documentation was the only activity in the
project with no external failure signal, so it expanded to fill the available time.

## 2. Rules

**R1 — Spec work is gated behind code, not traded against other spec work.**
No new spec *document* may be created while `STATE.md` shows an unstarted sprint. A trade rule
("defer something to add something") cannot be enforced, because the author can move a row
between columns in five seconds. A block rule can be enforced, including by a git hook.

**R2 — At most ONE open adversarial review at a time.**
Every finding must name an owning sprint step, or be closed as won't-fix. No review-of-a-review.
The three existing review documents total ~1,400 lines — 21% of the spec corpus — describing the
corpus rather than the game.

**R3 — Every sprint ends with a dated subjective play note in `STATE.md`.**
It must name at least one thing to change. "Feels fine" is a signature, not a signal. A sprint
whose only success criteria are machine-verifiable assertions has no error-correcting signal, and
this design's numbers (utility thresholds, entropy tax, toughness constants, stamina drain,
price curve) are all untested guesses.

**R4 — Budgets are test assertions, not tunable knobs.**
ADR-10 performance budgets and ADR-12 caps live in a read-only `budgets` block that tests read
and the tuning UI never exposes. A budget you can drag is not a budget.

**R6 — `RUNNING.md` is rewritten at the end of every sprint, before the PR opens.**
The play-tester must never have to deduce what is finished by poking at the build. Its "What to
test right now" section carries the current sprint's checks, what each one proves, and a SINGLE
not-built-yet list. Rewrite it; never append. This project has already accumulated three separate
"deliberately missing" sections written for three different sprints, all quietly wrong, which is
worse than having none — a stale list is read as authoritative. A sprint is done when someone
else can play it and knows what they are looking at, not when the suite is green.

**R5 — No effort estimates.** Team size is 1 and the owner knows it. An effort estimate for a
novel engine architecture by a solo developer is noise dressed as rigor, and producing one is a
day not spent writing code.

## 3. v0.1 — the first thing worth showing anyone

Ten items. Everything else is out.

1. Boot to a controllable player in a hand-authored test arena in under 2 seconds.
2. ECS-owned movement and collision that *feels* acceptable (no Godot physics nodes).
3. Picking / targeting via the ECS `PickSystem`.
4. Melee combat on the ADR-19 energy model, with health, death, and a corpse.
5. Physical inventory with volume and mass, and mass affecting movement speed.
6. One NPC with needs, a schedule, and a utility-driven daily routine.
7. Perception: sight cone + DDA line-of-sight, hearing with attenuation, witness events.
8. Fluid CA: water that spreads, freezes, and makes a floor slippery.
9. Debug surfaces: tick/perf strip, ECS entity inspector, perception overlay, spawn console.
10. A headless soak harness with committed metric baselines (ADR-20).

### v0.1 explicitly does NOT contain

The LLM reasoner. The node-graph spell compiler and Grimoire UI. More than one faction.
The death loop and Interregnum. Mutation. The semantic translation cipher. Procedural
world/floor generation. Player-facing HUD beyond a crosshair and a vitals readout.
Mid-run Save & Quit. The economy. Climate/weather. NavigationServer3D.

## 4. v0.2 — the world gets bigger

Procedural world/floor generation and chunk streaming. LoD boundary with conservation property
tests. Persistence (mid-run Save & Quit). The economy — scarcity, pricing, barter, crafting
stations. Player-facing HUD core with the Running Log and its spam aggregator.

## 5. Post-1.0 graveyard — named so it cannot ambush us

These are specified in detail and have **no owning sprint**. They are not cancelled; they are
explicitly deferred, which is different from being forgotten:

- HUD Edit Mode (draggable panels, viewport-% layout persistence). A AAA settings feature
  specified before any HUD exists.
- Intra-faction mutiny, succession, and full faction warfare beyond what the LLM objective
  layer needs.
- Per-culture language dictionaries beyond one worked example.
- Squad cohesion movement.
- Bounty Board.

## 6. Sprint ownership map (fills the verified gaps)

| Sprint | Owns |
|---|---|
| 0 | Scaffolding, CI, GUT, autoloads, InputMap, debug flag |
| 1 | The v0.1 list above. See the staged build order in `sprint_1_implementation_roadmap.md`. |
| 2 | World/floor generation, chunk streaming, macro tick, LoD boundary + conservation tests |
| **2.75 "The Market"** | **Previously unowned.** EconomySystem, Scarcity_Index, price formula, barter + change-making, merchant Trade_State, crafting stations, forges, alloys, recipes, ClimateSystem |
| P / 2.5 | Persistence contract, versioned save/load, migration hooks, settings menu skeleton |
| 3 | LLM bridge, prompt pipeline, validation gate, death loop, Interregnum, Lineage Journal |
| **3.5 "The Body Politic"** | **Previously unowned.** Loyalty, schism, succession by prestige, ClaimTags, caravans, grievance accumulation, war-time job generation, Job_Chat gossip, profession assignment |
| 4 | Chemistry reactions, spell compiler **plus the Grimoire UI that fronts it** |
| 5 | Content/data schemas and dictionaries, inventory UI, paper doll, quick-belt, acoustic encumbrance |
| 6 | LLM prompt tuning |
| **U "Interface & Accessibility"** | **Previously unowned.** HUD edit mode, GridFocusManager, escape stack, radial menu, keybind remapping, colorblind filters, font scaling, shake toggle, cipher toggle. Kept as one sprint deliberately — scattered accessibility does not ship. |

## 7. Iteration-speed budgets (enforced by test)

| Budget | Value | Why |
|---|---|---|
| Debug scenario → controllable | **≤ 2 s** | Paid ~50x/day. This is the number that governs daily life. |
| Full cold boot → controllable | **≤ 30 s** | A once-per-session cost. Print a per-phase breakdown so a regression is actionable. |
| Death → respawn (Interregnum) | **≤ 5 s** | **Previously unbudgeted anywhere.** This is the highest-frequency loading screen in a permadeath game and it lands at the moment of peak player frustration. |

A `--scenario=<name>` debug boot path (fixed RNG seeds, hand-authored chunk, no worldgen, no
pre-warm, `NullLLMProvider`) is a Sprint 1 deliverable. It is simultaneously the developer loop,
the substrate for every integration test, and the substrate for the ADR-20 soak harness.
