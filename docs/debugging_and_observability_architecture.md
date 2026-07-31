# Debugging & Observability Architecture

**Status:** Authoritative debug/telemetry contract. This defines visibility into the
simulation so systemic behavior can be tuned and explained without violating ECS ownership.

## 1. Purpose

The project needs first-class observability because "emergent" bugs can masquerade as good
simulation. Debug surfaces must answer:

- What happened?
- Which system caused it?
- Why did an entity choose that action?
- Which invariant changed?
- What did the player actually perceive?
- Where is the frame budget going?

## 2. Principles

- Observability reads ECS state; it does not mutate simulation state.
- Debug UI is a viewer/listener over ECSEvents and query APIs.
- Debug output must be deterministic enough for reproduction: include tick, entity handle,
  system name, RNG stream, and location.
- Debug data is bounded. Logs aggregate and sample; they do not emit per-cell/per-entity spam
  every Micro tick.
- Release builds may disable expensive traces, but invariant counters and fatal validation
  errors remain available.

## 3. Event trace model

Every meaningful simulation event should be representable as:

```json
{
  "tick": 12345,
  "clock": "Spring 1 14:00",
  "system": "PerceptionSystem",
  "event_type": "WitnessEventCreated",
  "entity": {"index": 42, "generation": 3},
  "target": {"index": 0, "generation": 8},
  "chunk_id": [1, 2, 0],
  "rng_stream": "combat",
  "summary": "Guard saw player steal coin stack",
  "data": {}
}
```

The event trace is a ring buffer with configurable capacity. It stores recent events for the
debug UI and can be dumped to `user://debug_traces/` on assertion failure.

## 4. Required counters

### Tick and performance
- Micro/Simulation/Macro tick durations.
- Per-system duration and entity count processed.
- Active entity count vs ADR-10 target/hard cap.
- Dirty CA cell updates per Micro tick.
- SpatialHash rebuild/update time.
- Path requests queued/completed/failed.
- Nav region dirty/rebake/fallback counts.

### ECS integrity
- Alive handle count.
- Component counts by registry.
- Stale handle validation failures.
- Destroy operations and dangling-reference removals.
- Query cache/archetype rebuild counts.

### Economy and LoD
- Faction ledgers by material.
- Materialized chunk count.
- MaterializationPolicy counts by policy.
- LoD transition counts.
- Ledgerized value vs manifest value.
- Boundary-conservation test counters.

### Perception and social
- Sight checks, LoS failures, and perceived targets.
- Noise events emitted/consumed.
- WitnessEvents created.
- MemoryEvents written and summarized to faction_memory.
- Guest_Status revocations with witness id.

### LLM
- Queue depth and in-flight request.
- Provider implementation in use.
- Prompt hash/cache hit.
- Request budget used.
- Timeout/invalid JSON/hallucinated target fallback counts.
- Objective changes by faction.

### Persistence
- Save duration and payload size.
- Load duration.
- Schema version.
- Migration count.
- Dirty topology persisted/rebuilt counts.

## 5. Debug overlays

### ECS inspector
Select an entity and show:
- EntityHandle, generation, alive/stale status.
- Components and fields.
- Ownership/faction/social identity.
- Current action queue and claimed job.
- Last N events involving this handle.
- Current LoD and materialization policy.

### Chunk inspector
Select a chunk and show:
- `chunk_id`, LoD state, biome tag.
- Active entities and Tier-1 population counters.
- Tile/topology/nav dirty flags.
- Volume pools and flood sources.
- Ledger/materialized state.
- CA dirty cell count.

### Perception overlay
Show:
- Sight cones and range.
- DDA LoS rays and blockers.
- Noise radii after attenuation.
- Last-known target markers.
- WitnessEvent creation points.

### Pathing/topology overlay
Show:
- AbstractGraph nodes/edges.
- Dirty/rebuilt edges.
- Active NavServer region status.
- Current path and fallback type.
- Edge progress for Simulated movers.

### Economy/LoD overlay
Show:
- Faction ledger totals.
- Physical commodity stacks.
- Identity manifests.
- Active/simulated/abstracted chunk boundaries.
- Conservation delta warnings.

### LLM/faction overlay
Show:
- Current objective/emotion.
- FactionCore memory salience.
- Prompt summary, valid targets, prompt hash.
- Queue position and fallback state.

## 6. "Why did this NPC do that?"

Every AI decision should expose a compact explanation record:

```json
{
  "entity": {"index": 112, "generation": 1},
  "tick": 7002,
  "decision": "Job_Investigate",
  "inputs": {
    "schedule": "Work",
    "need_interrupts": [],
    "perception": "Heard noise at (10,0,4); no LoS to player",
    "job_priority": 0.72
  },
  "rejected": [
    {"job": "Job_Combat", "reason": "No perceived hostile target"},
    {"job": "Job_Eat", "reason": "Hunger below threshold"}
  ]
}
```

This record lives in a bounded per-entity decision history, not in permanent save data unless
needed for a mid-run resume.

## 7. Logging policy

- Use event aggregation for repeated Micro tick events.
- Running Log UI aggregates player-facing events; debug trace keeps structured system events.
- Never log API keys, secrets, full prompts containing secrets, or user free-form notes unless
  explicitly exported by the player.
- LLM debug logs store prompt hash, compressed context summary, valid targets, schema result,
  and fallback reason. They do not store hidden chain-of-thought.

## 8. Assertion and failure policy

Debug builds should hard-fail on invariant violations:
- Duplicate materialization of a chunk.
- Negative ledger quantity.
- Stale handle dereference.
- Unknown component in save data without migration.
- UI direct ECS mutation attempt.
- Network LLM call during CI/test mode.

Release builds may surface a fatal error screen or safe-save path, but must not silently
continue after state corruption.

## 9. Sprint integration

- Sprint 0: create debug flag/config and ensure logs are writable under `user://`.
- Sprint 1: ECS inspector, tick counters, entity/component counts, perception overlay.
- Sprint 2: chunk/LoD/economy/topology overlays.
- Sprint P: save/load trace and schema/migration diagnostics.
- Sprint 3: LLM/faction prompt/fallback observability.
- Sprint 4: reaction/ephemeral/mutation traces.
- Sprint 5/6: content validation reports and prompt-compression reports.
