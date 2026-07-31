LLM Reasoner & Planning Architecture

Target Audience: Lead Coding Agent / AI Systems Architect
Context: This document outlines the system for integrating Large Language Models (LLMs) to drive Tier 3 entities (Faction Leaders, Unique NPCs, Bosses). The goal is to provide emergent, emotionally driven, and historically aware decision-making without stalling the game loop.

1. Core Philosophy: The CEO and the Workforce

The LLM does not micro-manage. It acts as the "CEO" of a faction.

The Reasoner (LLM): Operates asynchronously. It evaluates the macro-state of the world and sets high-level Objectives and Emotional States.

The Planner (Engine AI): The ECS (via GOAP or Utility AI) acts as the workforce. It receives the LLM's Objective and breaks it down into individual JobComponents for Tier 2 entities.

Crucial Constraint: The ECS must never wait on the LLM. The game continues running while the API call is in flight. Factions continue their current routines until the API returns a validated payload.

2. The Prompt Construction Pipeline (Lazy & Salient)

To prevent sending stale reality to the LLM, a prompt is only compiled the exact millisecond the request is fired to the API (Lazy Generation). Furthermore, to prevent token bloat, we strictly enforce a Salience Filter.

Context Layers:

Persona & History (From DAG): "You are Ug, Goblin King of Floor 3. Your faction was driven here 200 years ago by Dwarves."

Current State (From ECS): "Population: 45. Food: Low. Wealth: High."

Recent Events (The Salience Filter): The system parses the MemoryComponent and injects ONLY the 5 most recent chronological events, plus up to 3 "Core Memories" (events with a high_emotional_weight tag).

Valid Action Space (Anti-Hallucination): A strict list of valid high-level goals (GATHER_RESOURCES, RAID_FACTION, FORTIFY).

Valid Targets Enumeration: "Available target Faction IDs: [12: Dwarven Outpost, 14: The Player]."

3. Strict Output Contract (JSON Schema)

The LLM must be constrained to output strictly formatted JSON using Function Calling or Structured Outputs.

Expected JSON Structure:

{
  "thought_process": "We are starving. We must raid the gnomes for supplies.",
  "objective": "RAID_FACTION",
  "target_faction_id": 12,
  "emotion_state": "DESPERATE",
  "public_declaration": "Sharpen your blades! The gnomes hoard bread while we starve!"
}


4. Engine Translation & The Validation Gate

Once the JSON is received, it cannot be trusted implicitly. The world may have changed during the API latency.

Validation Gate: The Engine checks if the Faction Leader is still alive. It then checks if target_faction_id matches an active DAG node. If validation fails (due to LLM hallucination or world-state changes), the payload is rejected and the objective defaults to FORTIFY.

Job Generation: If validated, the objective (RAID_FACTION) is passed to the GOAP system, which translates it into ECS JobComponents (e.g., "Equip Weapons," "Pathfind to Target Zone") and pushes them to Tier 2 workers.

Flavor Text: The public_declaration is stored in the leader's MemoryComponent to be repeated by NPCs via the Gossip System.

5. Reasoning Triggers & Rate Limiting

LLMs are queried based on specific triggers, managed by a staggering queue to prevent API rate limits:

Time-Based (Macro Tick): Once every in-game week, a faction re-evaluates its grand strategy.

Crisis Triggers: Severe drops in population or taking direct damage immediately queues a Reasoning Tick.

Diplomatic Ping: The player speaking to a Tier 3 entity triggers a localized, conversational prompt execution.
