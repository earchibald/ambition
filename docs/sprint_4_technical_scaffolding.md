Sprint 4 Technical Scaffolding

Target Audience: Lead Coding Agent
Context: Concrete data structures and fail-safes for implementing modular magic and mutating biology.

1. Advanced Chemistry (The Reaction Matrix)

To prevent infinite loops of tags checking each other, reactions must be processed in a strict hierarchy during the Micro Tick, utilizing a cooldown.

# ReactionSystem.gd
const REACTION_MATRIX = {
    "Volatile_Gas+Burning": { "result_tags": ["Explosion", "Consumed"], "kinetic_force": 500, "temp_change": 800 },
    "Water+Burning": { "result_tags": ["Steam", "Extinguished"], "kinetic_force": 0, "temp_change": -100 }
}

func process_reactions(chunk_id):
    var entities = ECSManager.get_entities_in_chunk(chunk_id)
    # ... check overlapping bounding boxes/grids for tag combinations
    # ANTI-RECURSION PATCH
    # If reaction occurs, ECSManager.add_tag(entity_id, "Reaction_Cooldown", duration=1.0s)


2. The Spell Compiler (Anti-Crash Logic)

The engine cannot blindly execute user-generated logic loops or infinite geometry.

# SpellCompilerSystem.gd
class CompiledSpell extends RefCounted:
    var spell_id: String
    var strain_cost: float
    var trigger: String 
    var shape: String   
    var radius: float
    var catalysts: Array[Dictionary] 

func compile_runes(rune_array: Array) -> CompiledSpell:
    var spell = CompiledSpell.new()
    var total_complexity = 0
    
    for rune in rune_array:
        total_complexity += rune.complexity_value
        # GEOMETRIC PATCH: Hardcap spatial variables
        if rune.has("radius") and rune.radius > 15.0:
            rune.radius = 15.0 # Force override
        
    # ANTI-CRASH: Max Strain Check
    var player_insight = ECSManager.mind_components[0].insight_level
    if total_complexity > (player_insight * 1.5):
        print("Spell Compilation Failed: Exceeds cognitive limits.")
        return null 
        
    spell.strain_cost = total_complexity * 2.5
    return spell


3. Ephemeral Entities (The TTL Safeguard)

Magic MUST die. If a spell gets stuck, it will bloat the memory.

# ecs_components.gd
class EphemeralComponent extends RefCounted:
    var time_to_live: float = 5.0 # Maximum seconds this entity can exist
    var source_entity_id: int
    var payload: CompiledSpell

# Inside ActionResolutionSystem.gd (Micro Tick)
func process_ephemerals(delta):
    for entity in ephemerals:
        ephemerals[entity].time_to_live -= delta
        if ephemerals[entity].time_to_live <= 0.0:
            ECSManager.destroy_entity(entity) # FORCE CLEANUP


4. The Mutation Threshold

# MutationSystem.gd (Simulation Tick)
const MAX_MUTATIONS = 3 # Hard cap to prevent tag bloat and visual noise

func process_exposure(entity_id, delta):
    var body = ECSManager.body_components[entity_id]
    var current_chunk = ECSManager.positions[entity_id].chunk_id
    
    if WorldGrid.chunks[current_chunk].has_tag("Spores"):
        if not body.has_tag("Resist_Spores"):
            body.exposure_fungal += (delta * 0.5)
            
    if body.exposure_fungal >= 100.0:
        if body.active_mutations.size() < MAX_MUTATIONS:
            _trigger_mutation(entity_id, "FUNGAL")
        body.exposure_fungal = 0.0 # Reset to prevent triggering every tick


5. Integrated Corrections (ADR / Adversarial Review)

Authoritative note: governed by docs/architecture_decisions.md and the registry.

Reaction matrix keys (review F2): keys are the SORTED tag pair so order does not matter
("Burning+Volatile_Gas" == "Volatile_Gas+Burning"). Each rule declares scope: INTRA (two tags
on one entity) or INTER (two overlapping entities via SpatialHash). Keep the [Reaction_Cooldown]
anti-recursion lock. Prefer a data-driven rule list over a flat hardcoded dict as content grows.

Thermodynamics (review H2): temperature propagation uses the material/economy §7 heat model
(heat_capacity, energy = mass*heat_capacity*temp, conduction toward equilibrium). Add_Temperature
adds energy over mass, not a flat per-entity temperature.

Absorb_Tag conservation (review D8): Absorb consumes a quantified environmental resource
atomically (magic doc §6); concurrent absorbs cannot double-spend; a Fizzle results if the
required quantity is absent.

Aura/Ephemeral primitive: Sprint 4 magic BUILDS ON the Sprint 1 Ephemeral primitive
(entity_behavior §6); EphemeralComponent TTL cleanup is mandatory (§3 above).

Mutation -> faction alignment (review D3): the SocialSystem shift from player mutation tags
propagates via the witness/gossip reputation path (factions doc §6), not an instant hivemind;
the Spore-Lord shift toward neutral / Village toward hostile is a reputation delta, gossip-
propagated. Mutations reset on death; insight persists (magic doc §6).
