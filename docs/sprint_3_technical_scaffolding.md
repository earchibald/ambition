Sprint 3 Technical Scaffolding

Target Audience: Lead Coding Agent
Context: This document provides the concrete code structures, API safety mechanisms, and JSON schemas to implement sprint_3_implementation_roadmap.md. It includes critical patches for asynchronous race conditions, token management, and memory garbage collection.

AUTHORITATIVE CORRECTIONS (ADR): (1) LLM uses an LLMProvider interface over
OpenAI-compatible endpoints; { endpoint, api_key(from env/user:// — NEVER committed),
model } (ADR-5). Tests inject a NullLLMProvider stub so headless CI makes no network calls.
(2) "Translate objective to GOAP jobs" is, for now, deterministic objective->JobTemplate
expansion (ADR-4), not true GOAP. (3) The Interregnum Entropy/Swarm Tax operates on LEDGERS
and abstract population counters, not physical entities — during the skip the world is
Abstracted and wealth lives in ledgers, so an entity-only tax barely applies (review C2 /
ADR-11). See corrected code below. (4) Player identity: Entity 0 = Faction 0 with a
synthetic DAG node so targeting the player validates (ADR-14).

1. The LLM Bridge & Asynchronous Queue (Lazy Generation)

Do not block the main thread. Do not store stale prompts.

# LLMBridge.gd (Autoload)
var request_queue: Array[int] = [] # Store ONLY entity_ids
var is_request_in_flight: bool = false
var http_node: HTTPRequest

func _ready():
    http_node = HTTPRequest.new()
    add_child(http_node)
    http_node.request_completed.connect(_on_request_completed)

func _process(delta):
    if not is_request_in_flight and request_queue.size() > 0:
        _dispatch_next_request()

func request_reasoning(entity_id: int):
    if not request_queue.has(entity_id):
        request_queue.append(entity_id)

func _dispatch_next_request():
    is_request_in_flight = true
    var entity_id = request_queue.pop_front()
    
    # LAZY GENERATION: Build the prompt right now, not when queued.
    var real_time_prompt = PromptBuilderSystem.build_context(entity_id)
    _send_to_api(real_time_prompt)


2. LLM Output Schema (Strict JSON Contract)

The prompt MUST instruct the LLM to return this exact schema.

// Required LLM Output Schema
{
  "thought_process": "string (Max 200 chars for dev logging)",
  "objective": "Enum: [FORTIFY, RAID_FACTION, GATHER_RESOURCES, MIGRATE, IDLE]",
  "target_faction_id": "integer (Must match an ID provided in the prompt's Valid Targets list)",
  "emotion_state": "Enum: [CALM, FEARFUL, AGGRESSIVE, DESPERATE]",
  "public_declaration": "string (Short dialogue bark for NPCs)"
}


3. The Validation Gate (Anti-Race & Anti-Hallucination)

# LLMResolutionSystem.gd
func _on_request_completed(result, response_code, headers, body):
    var json = JSON.parse_string(body.get_string_from_utf8())
    var entity_id = current_flight_data.entity_id
    
    # 1. Check if the Leader is still alive
    if not ECSManager.is_alive(entity_id):
        return
        
    # 2. Anti-Hallucination & Reality Check
    var target_id = json.get("target_faction_id", -1)
    if target_id != -1 and not DAG.has_active_faction(target_id):
        print("LLM Call Aborted: Hallucinated or destroyed target.")
        json["objective"] = "FORTIFY" # Safe Fallback
        
    # 3. Validation passed. Translate to GOAP Jobs.
    _translate_objective_to_jobs(entity_id, json)


4. The Interregnum & Entropy Tax (Garbage Collection)

# MetaProgressionManager.gd
func execute_interregnum():
    # 1. Update DAG
    DAG.add_event_edge(0, "Killed_By", last_attacker_id)
    
    # 2. Macro-Tick Burst
    for month in range(12):
        ECSManager.process_macro_tick()
        
    # 3. THE ENTROPY & SWARM TAX (ADR-11: operate on LEDGERS, not physical entities)
    # During the skip the world is Abstracted, so wealth lives in FactionCore ledgers and
    # swarms in population counters. Tax those, not PhysicalPropertyComponent entities.
    for faction_id in DAG.get_active_factions():
        var ledger = ECSManager.faction_cores[faction_id].abstract_wealth_ledger
        for mat in ledger.keys():
            ledger[mat] = int(ledger[mat] * 0.60) # 40% wealth entropy tax on the ledger
    # Residual physical-entity GC (clears any stray loose items / filth left Active):
    var all_physical_items = ECSManager.get_all_entities_with_component("PhysicalPropertyComponent")
    for item_id in all_physical_items:
        if ECSManager.has_tag(item_id, "Filth") or ECSManager.has_tag(item_id, "Scrap"):
            ECSManager.destroy_entity(item_id)
        elif not ECSManager.has_component(item_id, "OwnershipComponent"):
            if randf() < 0.40:
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
# NullLLMProvider (tests/CI): immediately returns a canned valid {"objective":"FORTIFY",...}.
#
# Config: endpoint + model in a committed config file with env-var overrides; api_key is read
# from an env var or user:// and is NEVER committed (add the key file path to .gitignore).
# Cache responses by prompt hash within a run; keep the staggered queue + per-session budget.

6. Objective -> JobTemplate Expansion (ADR-4, replaces "GOAP" for now)

_translate_objective_to_jobs() looks up a data-driven JobTemplate table instead of running a
GOAP planner:
    JOB_TEMPLATES = {
      "RAID_FACTION":     [Equip@armory, FormSquad, PathfindTo(target.anchor), Siege],
      "GATHER_RESOURCES": [ClaimResourceZones, AssignHaulers, Restock@stockpile],
      "FORTIFY":          [ReassignToGuard(ratio), PatrolBorders, Barricade@chokepoints],
      ...
    }
The faction planner instantiates the template's job types, profession-filters them onto Tier-2
workers, and selects targets via target_selector. The planner exposes plan(objective, faction)
-> jobs so a true GOAP planner can be swapped in later behind the same interface.
