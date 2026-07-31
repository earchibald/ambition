LLM Reasoner & Planning Architecture

Target Audience: Lead Coding Agent / AI Systems Architect
Context: This document outlines the system for integrating Large Language Models (LLMs) to drive Tier 3 entities (Faction Leaders, Unique NPCs, Bosses). The goal is to provide emergent, emotionally driven, and historically aware decision-making without stalling the game loop.

1. Core Philosophy: The CEO and the Workforce

The LLM does not micro-manage. It acts as the "CEO" of a faction.

The Reasoner (LLM): Operates asynchronously. It evaluates the macro-state of the world and sets high-level Objectives and Emotional States.

The Planner (Engine AI): The ECS expands the LLM's Objective through deterministic,
data-driven JobTemplates (ADR-4). It receives the objective and breaks it down into
individual JobComponents for Tier 2 entities. A true search planner is reserved for a future
implementation behind the same `plan(objective, faction) -> jobs` interface.

Crucial Constraint: The ECS must never wait on the LLM. The game continues running while the API call is in flight. Factions continue their current routines until the API returns a validated payload.

2. The Prompt Construction Pipeline (Lazy & Salient)

To prevent sending stale reality to the LLM, a prompt is only compiled the exact millisecond the request is fired to the API (Lazy Generation). Furthermore, to prevent token bloat, we strictly enforce a Salience Filter.

Context Layers:

Persona & History (From DAG): "You are Ug, Goblin King of Floor 3. Your faction was driven here 200 years ago by Dwarves."

Current State (From ECS): "Population: 45. Food: Low. Wealth: High."

Recent Events (The Salience Filter): The system parses faction_memory / MemoryComponent and
injects ONLY the top 3 memories by decayed weight plus the 3 most recent chronological events.

Valid Action Space (Anti-Hallucination): A strict list of valid high-level goals (GATHER_RESOURCES, RAID_FACTION, FORTIFY).

Valid Targets Enumeration: "Available target Faction IDs: [12: Dwarven Outpost, 0: The Player]." (The player is Faction 0 per ADR-14.)

3. Strict Output Contract (JSON Schema)

The LLM must be constrained to output strictly formatted JSON using Function Calling or Structured Outputs.

Expected JSON Structure:

{
  "reason_summary": "Food is low and the gnomes are the nearest viable target.",
  "objective": "RAID_FACTION",
  "target_faction_id": 12,
  "emotion_state": "DESPERATE",
  "public_declaration": "Sharpen your blades! The gnomes hoard bread while we starve!"
}


4. Engine Translation & The Validation Gate

Once the JSON is received, it cannot be trusted implicitly. The world may have changed during the API latency.

Validation Gate: The Engine checks if the Faction Leader is still alive. It then checks if target_faction_id matches an active DAG node. If validation fails (due to LLM hallucination or world-state changes), the payload is rejected and the objective defaults to FORTIFY.

Job Generation: If validated, the objective (RAID_FACTION) is passed to the JobTemplate
planner, which expands it into ECS JobComponents (e.g., "Equip Weapons," "Pathfind to Target
Zone") and pushes them to Tier 2 workers.

Flavor Text: The public_declaration is stored in the leader's MemoryComponent to be repeated by NPCs via the Gossip System.

5. Reasoning Triggers & Rate Limiting

LLMs are queried based on specific triggers, managed by a staggering queue to prevent API rate limits:

Time-Based (Macro Tick): Once every in-game week, a faction re-evaluates its grand strategy.

Crisis Triggers: Severe drops in population or taking direct damage immediately queues a Reasoning Tick.

Diplomatic Ping: The player speaking to a Tier 3 entity triggers a localized, conversational prompt execution.

6. Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and the registry.

Provider (ADR-5): OpenAI-compatible endpoints via an LLMProvider interface; config is
{ endpoint, model } (committed, env-overridable) + api_key (env/user://, NEVER committed).
Tests/CI inject a NullLLMProvider stub returning a canned valid FORTIFY payload. Structured
output uses response_format {"type":"json_object"} (or provider equivalent). Identical prompts
are cached by hash within a run to control cost; the staggered queue caps request rate.

AI backbone (ADR-4): the Planner uses data-driven JobTemplates (Sprint 3 §6), with the
implementation hidden behind `plan(objective, faction) -> jobs` so a search planner can be
swapped in later if needed.

Player identity (ADR-14): the player is Faction 0 with a synthetic Faction-0 DAG node, so
"target the player" validates in the Validation Gate. The older "14: The Player" example is
void; enumerate the player as its real Faction-0 id in Valid Targets.

Abstracted-faction context (review B6): salient memories come from
FactionCoreComponent.faction_memory (registry §4), which macro systems keep fresh even when
the faction has no individuals. The Salience Filter selects top-3 by weight + 3 most recent
(weight/decay model in factions doc §6).

Conversation UX under "never block" (review F1): a Diplomatic Ping (player speaks to a Tier-3
entity) fires an async request but the ECS never stalls. The NPC immediately emits a diegetic
"thinking" bark from a local table; when the response lands, the real line replaces it. On
timeout/error, a fallback line is shown and the current objective is maintained until the next
Macro reasoning opportunity.

Output rationale: the schema uses `reason_summary` (brief audit text, max 200 chars); do not
request hidden chain-of-thought-style output from the provider.
Fallback Matrix: timeout -> maintain current objective and requeue next Macro tick; invalid
JSON -> FORTIFY; hallucinated/invalid target -> FORTIFY with target stripped.
