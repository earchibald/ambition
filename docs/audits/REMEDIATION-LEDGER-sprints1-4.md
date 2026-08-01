# Remediation Ledger — Sprints 1–4 full audit pass (2026-08-01)

Working ledger for the full-audit/gap-fill/remediation pass. One row per item. Status moves
`OPEN -> FIXED | DECLARED | REMOVED`. "DECLARED" means: recorded as not-built, with a reason,
in the final manifest — never silently.

Sources: the two published gap lists (Sprint 3/3.5 manifest §4b, Sprint 4 manifest §6), plus
four fresh audit sweeps run 2026-08-01: S12 (Sprints 1–2 spec-vs-code), S35 (Sprint 3/3.5
beyond §4b), S4X (Sprint 4 + cross-cutting), DS (dead-symbol sweep, 72 findings).

## Wave 1 — Sprint 3 reasoning stack (declared gaps + sweep blockers)

| ID | Item | Status |
|---|---|---|
| W1-1 | Queue priority classes (crisis > diplomatic > routine), FIFO within class [§4b G-5] | FIXED |
| W1-2 | ADR-12 faction cap enforced before enqueue [§4b G-1] | FIXED |
| W1-3 | `reason_summary`/`public_declaration` 200-char cap enforced on ingest [§4b G-4] | FIXED |
| W1-4 | Thinking bark: `faction_thinking` signal + overlay feed line [§4b G-2] | FIXED |
| W1-5 | Adventurer's Residence carved in origin village chunk; world spawn uses it [§4b G-3] | FIXED |
| W1-6 | Sprint 3 perf gates: arena ≤2 s, death→respawn ≤5 s, pump budget [§4b G-6, S4X-18] | OPEN |
| W1-7 | `counters()` merge missing planner/reasoning/llm/locomotion/death_loop/streaming/economy — F1 showed zeros forever [S35-12] | OPEN |
| W1-8 | Planner jobs preempted in one sim tick: `score_at_claim` never set by planner [S35-8] | OPEN |
| W1-9 | ProfessionComponent never attached in production + `Prof_*` vocabulary mismatch [S35-1,2] | OPEN |
| W1-10 | Faction memory: decay applied at read, cap 64, evict lowest-weight non-core [S35-5,6] | OPEN |
| W1-11 | Timeout requeues next Macro tick, as the fallback matrix specifies [S35-9] | OPEN |
| W1-12 | Spawn-faction NEUTRAL floor at re-entry (explicit clamp, not arithmetic accident) [S35-14] | OPEN |
| W1-13 | `release_jobs_of` + `mark_precondition_failed` wired to production (death, path failure) [S35-15, DS] | OPEN |
| W1-14 | Swarms: worldgen seeds them, interregnum breeds them, cap becomes reachable [S35-3] | OPEN |
| W1-15 | Committed LLM config file with env-var override [S35-16] | OPEN |
| W1-16 | Guest_Status + wealth-derived starting kit at spawn [S12-2] | FIXED |
| W1-17 | Leader memories in prompt (`leader_memories`) [§4b G-8] | FIXED |
| W1-18 | Declaration into leader MemoryComponent so gossip can repeat it [§4b G-9] | FIXED |
| W1-19 | `most_salient` unstable single-field sort — total order [DS + STATE.md warning] | FIXED |
| W1-20 | `player_died`/`player_reborn` had zero listeners — feed lines added [DS] | FIXED |

## Wave 2 — Sprint 3.5 social layer (the absent spec systems)

| ID | Item | Status |
|---|---|---|
| W2-1 | `leader_handle` on FactionCoreComponent; leader designated at materialization | PARTIAL (field added) |
| W2-2 | Succession by prestige: leader dies -> highest-prestige member promoted, crisis reasoning queued [§4b, "most damning row"] | OPEN |
| W2-3 | Loyalty recalculated on Simulation tick from needs/memory/faction wealth; loyalty read | OPEN |
| W2-4 | Schism at loyalty threshold: splinter faction, WAR both ways, ADR-12 cap respected | OPEN |
| W2-5 | WAR has a behavioural consumer: hostile citizens engage on sight [S35-4] | OPEN |
| W2-6 | Brawls: contested resources between non-allied factions -> non-lethal fights -> grievances | OPEN |
| W2-7 | ClaimTags: chunks carry a claiming faction; planner respects claims [§4b] | OPEN |
| W2-8 | TRADE status reachable (`status_for` band) + Trade Mission caravans: real carrier, real goods, interceptable [§4b] | OPEN |
| W2-9 | Prestige assigned at spawn (deterministic RNG), read by succession | OPEN |

## Wave 3 — Sprint 4 + cross-cutting

| ID | Item | Status |
|---|---|---|
| W3-1 | Burning does something: DoT on biomass, heats the carrier, expires; braziers burn down [S4X-1] | OPEN |
| W3-2 | Quench works: Burning+Water SCOPE_BOTH; Water/Wet vocabulary unified [S4X-2] | OPEN |
| W3-3 | Strain per spec: temporary Max_Stamina damage, recovered by rest; stamina regains at rest at all [S4X-3] | OPEN |
| W3-4 | Event trace: ring buffer, flag-gated, dumpable to user://debug_traces [S4X-4, S12-10] | OPEN |
| W3-5 | Insight can grow in play (kills/butchery/lectern) [S4X-5] | OPEN |
| W3-6 | Explosion/Smoke: expiry + a consumer (smoke attenuates LoS — also fixes S12-7 steam gap) | OPEN |
| W3-7 | Registry corrected: body fields, Sprint 3/4 component drift both directions [S4X-7,8, S35-10,11] | OPEN |
| W3-8 | Ignition temperature model [§6 G-7] | OPEN |
| W3-9 | Natural hazard zones in worldgen ruins [§6 G-11] | OPEN |
| W3-10 | Rune learning in play: lectern prop + ruined-library grants [§6 G-3] | OPEN |
| W3-11 | Spell visuals: payload-coloured, emissive [§6 G-4] | OPEN |
| W3-12 | Overclocking + mishap table + Mercy Cap [§6 G-2] | OPEN |
| W3-13 | Pre-Warm actually runs in the shipped boot [S12-1] | OPEN |
| W3-14 | Soak harness: --soak flag, CSV dump, committed baseline [S12-5, ADR-20] | OPEN |
| W3-15 | Spawn console + free camera [S12-6] | OPEN |
| W3-16 | Noise events loudest-first; listener cap counts only hearers, nearest-first [S12-13] | OPEN |
| W3-17 | Perception overlay flag wired (NPC sight circles); fluid overlay flag honest [S12-9, S4X-12] | OPEN |
| W3-18 | Boot per-phase timing breakdown [S12-12] | OPEN |
| W3-19 | DAG compaction at interregnum [S12-16] | OPEN |
| W3-20 | Projectile boundary crossing: real DDA against the target chunk [S12-14] | OPEN |
| W3-21 | Cross-LoD combat branch stated in ActionResolutionSystem [S12-15] | OPEN |
| W3-22 | `conduct_pair` wired: burning/hot bodies heat what they touch [DS] | OPEN |
| W3-23 | `spawn_noise` wired: detonations are audible, unseen impacts -> INVESTIGATE [DS] | OPEN |
| W3-24 | `tick_completed` consumed by the overlay instead of a poll [DS] | OPEN |
| W3-25 | HeatSource fields live: output per tick, max temp, burnout [DS, S4X-8] | OPEN |
| W3-26 | Job lifecycle honest: DONE reachable on arrival; ABORTED on release [DS] | OPEN |
| W3-27 | Dead-symbol cull: delete unwired helpers, or wire them; every survivor justified [DS ×72] | OPEN |

## Declared (not built this pass, with reasons — final list lives in the manifest)

- AbstractGraph reconstruction (S12-3) and topology dirty consumers (S12-4): no production
  tile mutation exists yet; wiring a rebuild with no writer would be dead code with a test.
- Perception sector bitset + amortized slices (S12-8): recorded substitution (cap for
  amortization); needs its own perf sprint next to the ADR-10 port.
- NavBridge request/response handshake (S12-17): bounded synchronous pathfinding satisfies the
  stated intent; recorded as a resolved ambiguity.
- Grimoire node-graph editor / hologram / cipher (G-1), gas physics (G-8), NPC casting (G-5),
  guards/tavern gating (G-10 beyond hostility), Rust/GDExtension port (G-12).
- Material cost for spells (S4X-10), disease branch of exposure (S4X-17), protective gear
  items (S4X-16): content axes; vocabulary exists, content sprint owns them.
- Absorb-at-caster vs absorb-on-collision + no [Spark] fizzle (S4X-6): recorded as a resolved
  ambiguity with rationale (C-D13), was undeclared before this pass.
- "Why did this NPC do that" explanation records (S4X-13); hard_fail flag consumers (S4X-11).
- Interregnum world evolution beyond taxes (S35-13); macro writers of faction memory (S35-7).
