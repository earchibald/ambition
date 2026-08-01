Sprint 3 Technical Scaffolding

Target Audience: Lead Coding Agent
Context: This document provides the concrete code structures, API safety mechanisms, and JSON schemas to implement sprint_3_implementation_roadmap.md. It includes critical patches for asynchronous race conditions, token management, and memory garbage collection.

AUTHORITATIVE CORRECTIONS (ADR): (1) LLM uses an LLMProvider interface over
OpenAI-compatible endpoints; { endpoint, api_key(from env/user:// — NEVER committed),
model } (ADR-5). Tests inject a NullLLMProvider stub so headless CI makes no network calls.
(2) Objective translation is, for now, deterministic objective->JobTemplate
expansion (ADR-4), not a search planner. (3) The Interregnum Entropy/Swarm Tax operates on LEDGERS
and abstract population counters, not physical entities — during the skip the world is
Abstracted and wealth lives in ledgers, so an entity-only tax barely applies (review C2 /
ADR-11). See corrected code below. (4) Player identity: Entity 0 = Faction 0 with a
synthetic DAG node so targeting the player validates (ADR-14).

1. The LLM Bridge & Asynchronous Queue (Lazy Generation)

Do not block the main thread. Do not store stale prompts.

# LLMBridge.gd (Autoload)
var request_queue: Array[EntityHandle] = [] # Store ONLY handles; build prompts lazily
var is_request_in_flight: bool = false
var http_node: HTTPRequest

func _ready():
    http_node = HTTPRequest.new()
    add_child(http_node)
    http_node.request_completed.connect(_on_request_completed)

func _process(delta):
    if not is_request_in_flight and request_queue.size() > 0:
        _dispatch_next_request()

func request_reasoning(entity: EntityHandle):
    if not request_queue.has(entity):
        request_queue.append(entity)

func _dispatch_next_request():
    is_request_in_flight = true
    var entity = request_queue.pop_front()
    current_flight_data = { "entity": entity }   # CORRECTION 2026-08-01, see note below

    # LAZY GENERATION: Build the prompt right now, not when queued.
    var real_time_prompt = PromptBuilderSystem.build_context(entity)
    _send_to_api(real_time_prompt)


2. LLM Output Schema (Strict JSON Contract)

The prompt MUST instruct the LLM to return this exact schema.

// Required LLM Output Schema
{
  "reason_summary": "string (Max 200 chars for dev logging; brief rationale, not chain-of-thought)",
  "objective": "Enum: [FORTIFY, RAID_FACTION, GATHER_RESOURCES, MIGRATE, IDLE]",
  "target_faction_id": "integer (Must match an ID provided in the prompt's Valid Targets list)",
  "emotion_state": "Enum: [CALM, FEARFUL, AGGRESSIVE, DESPERATE]",
  "public_declaration": "string (Short dialogue bark for NPCs)"
}


3. The Validation Gate (Anti-Race & Anti-Hallucination)

# LLMResolutionSystem.gd
func _on_request_completed(result, response_code, headers, body):
    # CORRECTION 2026-08-01. THIS MUST BE THE FIRST LINE, before any early return below.
    # As originally written this function never cleared the flag, so the queue deadlocked on
    # its first request and Tier-3 reasoning stopped for the rest of the session.
    is_request_in_flight = false

    var json = JSON.parse_string(body.get_string_from_utf8())
    var entity = current_flight_data.entity

    # 1. Check if the Leader is still alive
    if not ECSManager.is_alive(entity):
        return


    # 2. Anti-Hallucination & Reality Check
    var target_id = json.get("target_faction_id", -1)
    if target_id != -1 and not DAG.has_active_faction(target_id):
        print("LLM Call Aborted: Hallucinated or destroyed target.")
        json["objective"] = "FORTIFY" # Safe Fallback
        
    # 3. Validation passed. Expand objective via JobTemplates.
    _translate_objective_to_jobs(entity, json)


4. The Interregnum & Entropy Tax (Garbage Collection)

# MetaProgressionManager.gd
func execute_interregnum():
    # 1. Update DAG
    DAG.add_event_edge(0, "Killed_By", last_attacker_id)
    
    # 2. Macro-Tick Burst
    for month in range(12):
        ECSManager.process_interregnum_month()
        
    # 3. THE ENTROPY & SWARM TAX (ADR-11: operate on LEDGERS, not physical entities)
    # During the skip the world is Abstracted, so wealth lives in FactionCore ledgers and
    # swarms in population counters. Tax those, not PhysicalPropertyComponent entities.
    for faction_id in DAG.get_active_factions():
        var ledger = ECSManager.faction_cores[faction_id].abstract_wealth_ledger
        for mat in ledger.keys():
            ledger[mat] = int(ledger[mat] * 0.60) # 40% wealth entropy tax on the ledger
    # Residual physical-entity GC (clears any stray loose items / filth left Active):
    var all_physical_items = ECSManager.query(ECSManager.MASK_PHYSICAL) # archetype query (ADR-13)
    for item_id in all_physical_items:
        if ECSManager.has_tag(item_id, "Filth") or ECSManager.has_tag(item_id, "Scrap"):
            ECSManager.destroy_entity(item_id)
        elif not ECSManager.has_component(item_id, "OwnershipComponent"):
            if RNGService.roll(&"economy") < 0.40:
                ECSManager.destroy_entity(item_id)
                
    # CRITICAL: Prevent Swarm Exponential Crash (abstract counter, ADR-11)
    for chunk_id in WorldGrid.get_all_chunks():
        if WorldGrid.chunks[chunk_id].swarm_population > 10:
             WorldGrid.chunks[chunk_id].swarm_population = 10


5. LLMProvider Interface & Config (ADR-5)

# LLMProvider.gd (interface)
#   func request(prompt: String, schema: Dictionary, on_done: Callable) -> void
# OpenAICompatibleProvider: POST {endpoint}/chat/completions with
#   response_format = {"type": "json_object"}, model = {model}, Authorization: Bearer {api_key}.
# CORRECTION 2026-08-01: this line contradicted the ADR-5 amendment and is superseded.
# The amendment promotes the local provider from a test stub to a SHIPPED product mode, and
# requires it to decide from real faction state rather than return a canned payload. A canned
# FORTIFY makes the no-endpoint build unplayable, which is the exact case the amendment exists
# to protect. Implemented as `HeuristicProvider`, which scores starvation, threat and
# opportunity from the same context Dictionary the remote provider receives.
#
# Config: endpoint + model in a committed config file with env-var overrides; api_key is read
# from an env var or user:// and is NEVER committed (add the key file path to .gitignore).
# Cache responses by prompt hash within a run; keep the staggered queue + per-session budget.

6. Objective -> JobTemplate Expansion (ADR-4)

_translate_objective_to_jobs() looks up a data-driven JobTemplate table instead of running a
search planner:
    JOB_TEMPLATES = {
      "RAID_FACTION":     [Equip@armory, FormSquad, PathfindTo(target.anchor), Siege],
      "GATHER_RESOURCES": [ClaimResourceZones, AssignHaulers, Restock@stockpile],
      "FORTIFY":          [ReassignToGuard(ratio), PatrolBorders, Barricade@chokepoints],
      ...
    }
The faction planner instantiates the template's job types, profession-filters them onto Tier-2
workers, and selects targets via target_selector. The planner exposes plan(objective, faction)
-> jobs so a true search planner can be swapped in later behind the same interface.

7. Integrated Corrections (open review items landing in Sprint 3)

Abstracted-faction memory (review B6): PromptBuilderSystem reads
FactionCoreComponent.faction_memory for salient context (populated by macro systems), so a
leader's prompt is fresh even with no individual Tier-2 entities. Salience = top-3 by weight +
3 most recent (weight/decay per factions doc §6).

Faction cap enforcement (ADR-12): before queuing a new Tier-3 leader (schism/succession/
migration), enforce the faction cap (default 24); if exceeded, merge/abstract the weakest
first so the ReasoningQueue and diplomacy matrix stay bounded.

Conversation UX (review F1): a Diplomatic Ping never blocks — emit a local "thinking" bark
immediately, replace it when the async response lands, and show a fallback line on timeout
(FallbackMatrix: timeout -> maintain current objective and requeue next Macro tick; invalid
JSON -> FORTIFY; hallucinated target -> FORTIFY with target stripped). See llm doc §6.

Interregnum (ADR-11): the Entropy/Swarm Tax operates on ledgers + swarm counters (already
corrected in §4). Add the player-death DAG edge to the synthetic Faction-0 node (ADR-14).
