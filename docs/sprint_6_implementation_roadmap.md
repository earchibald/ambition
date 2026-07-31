Implementation Roadmap: Sprint 6 (LLM Prompt Fine-Tuning)

Target Audience: Lead Coding Agent / AI Prompt Engineer
Objective: Finalize the pipeline that translates ECS game state into LLM context, and strictly validate the LLM's JSON response back into GOAP actionables. This sprint focuses on token efficiency and hallucination prevention.

Step 1: The Context Compressor (Token Economy)

The Objective: The LLM cannot read the entire ECS memory. The context must be heavily compressed into YAML or a CSV-like string before being injected into the prompt.
Required Implementation:

Build ContextCompressor.gd.

Rules:

Do not send raw component JSON.

Bad: {"InventoryComponent": {"held_volume": 40, "items": [{"id": "MAT_IRON", "qty": 5}]}}

Good (Compressed): Stockpile: 5 Iron, 10 Meat.

Strip all Godot-specific logic (EntityID, Vector3). Use relative terms: Nearest Enemy: Player (Distance: Close).

Step 2: The Salience Filter (Memory Extraction)

The Objective: Provide the LLM with a sense of time and grudge without overloading the context window.
Required Implementation:

Implement the chronological extractor.

Sort the faction's MemoryComponent by a Weight float.

Pass only the top 3 Highest Weight memories (Core Memories) and the 3 Most Recent memories.

Example Output: Recent History: 1. Player killed 3 guards. 2. Stockpile ran out of food. 3. Spiders attacked western border.

Step 3: The System Prompt Template

The Objective: Hardcode the unyielding rules of reality the LLM must abide by.
Required Implementation:

Create a master template:

You are {leader_name}, leader of {faction_name}.
Personality: {culture_tags}.

CURRENT STATE:
{compressed_context}

RECENT MEMORIES:
{salient_memories}

YOUR AVAILABLE TARGETS:
{valid_targets_list}

TASK: Determine your faction's grand objective. You MUST respond in valid JSON matching the schema below.


Step 4: Strict Schema Validation & The Fallback Matrix

The Objective: Ensure the game never crashes when the LLM outputs broken JSON, hallucinates an action, or fails to respond.
Required Implementation:

Ensure the API call strictly uses response_format: { type: "json_object" } (or equivalent structured outputs for the chosen model).

Build the FallbackMatrix in LLMResolutionSystem.gd:

Error: Network Timeout -> Action: Re-queue for next Macro Tick, maintain current objective.

Error: Invalid JSON -> Action: Default to FORTIFY, log error for dev.

Error: Hallucinated Target ID -> Action: Strip target, default to GATHER_RESOURCES.

Step 5: Integrated Corrections (ADR / Adversarial Review)

Provider (ADR-5): OpenAI-compatible endpoints; response_format {"type":"json_object"} (or
provider structured-output equivalent). api_key from env/user:// (never committed). Tests use
NullLLMProvider. Cache by prompt hash; stagger to respect rate limits.

Salience weight/decay (review F3): MemoryEvent.weight = base_weight(event_type) *
recency_falloff(age) + emotional_bonus(core). Select top-3 by weight (Core Memories) + 3 most
recent. Decay applied on the Macro tick; core memories decay slowly. Abstracted factions draw
from FactionCoreComponent.faction_memory (review B6).

Context source: compress from faction_memory + FactionCoreComponent ledger/diplomacy, using
relative terms (Nearest Enemy: Player (Close)) and the canonical Faction-0 id for the player
(ADR-14). FallbackMatrix handles timeout / invalid JSON / hallucinated target.
