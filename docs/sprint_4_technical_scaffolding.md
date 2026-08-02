Sprint 4 Technical Scaffolding

Target Audience: Lead Coding Agent
Context: Concrete data structures and fail-safes for implementing modular magic and mutating biology.

1. Advanced Chemistry (The Reaction Matrix)

To prevent infinite loops of tags checking each other, reactions must be processed in a strict hierarchy during the Micro Tick, utilizing a cooldown.

# ReactionSystem.gd
const REACTION_RULES = [
    {
        "tags": [&"Burning", &"Volatile_Gas"], # sorted at load; A+B == B+A
        "scope": &"INTER", # or &"INTRA"
        "result_tags": [&"Explosion", &"Consumed"],
        "kinetic_force": 500,
        "energy_delta": 800
    },
    {
        "tags": [&"Burning", &"Water"],
        "scope": &"INTER",
        "result_tags": [&"Steam", &"Extinguished"],
        "kinetic_force": 0,
        "energy_delta": -100
    }
]

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
    # MindComponent.insight is Dictionary{StringName:int} (registry §2). Spell compilation is
    # gated on the Rune_Stability key specifically, NOT on the Dictionary itself.
    var mind = ECSManager.minds[ECSManager.player_handle()]
    var player_insight: int = mind.insight.get(&"Rune_Stability", 0)
    if total_complexity > (float(player_insight) * 1.5):
        print("Spell Compilation Failed: Exceeds cognitive limits.")
        return null 
        
    spell.strain_cost = total_complexity * 2.5
    return spell


3. Ephemeral Entities (The TTL Safeguard)

Magic MUST die. If a spell gets stuck, it will bloat the memory.

# ecs_components.gd
class EphemeralComponent extends RefCounted:
    var time_to_live: float = 5.0 # Maximum seconds this entity can exist
    var source_entity: EntityHandle
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
            body.exposure[&"Fungal"] = body.exposure.get(&"Fungal", 0.0) + (delta * 0.5)
            
    if body.exposure.get(&"Fungal", 0.0) >= 100.0:
        if body.mutations.size() < MAX_MUTATIONS:
            _trigger_mutation(entity_id, "FUNGAL")
        body.exposure[&"Fungal"] = 0.0 # Reset to prevent triggering every tick


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


6. Corrections made during implementation (2026-08-01)

Dated in place rather than silently fixed, because a future agent copy-pasting from the sketches
above would reintroduce each of these. The code is authoritative; these notes say why it differs.

§1 REACTION SCOPE NEEDS A THIRD VALUE. The sketch offers INTRA and INTER. Fire spread needs BOTH,
and the omission was a live hole rather than a nicety: a fireball whose catalyst tags a spore
cloud `Burning` leaves ONE entity carrying `Burning` and `Spores`, and an INTER-only rule never
matches a pair that lives on a single entity. The roadmap's own success state — a torch into a
room of spores — therefore produced nothing at all, while every unit test passed, because they all
arranged the two tags on two neighbouring entities. `ReactionSystem.SCOPE_BOTH` registers one
authored rule under both keys.

§1 `energy_delta: 800` IS NOT A UNIT. The rule table's energy figures are gone. A rule now names
WHICH participant burns, and `MaterialLibrary.combustion_energy_j` derives the joules from that
body's mass and its heat of combustion — so a spore cloud (1.9 MJ) and a barn do not release the
same energy because someone typed a number. The ambient rise is then real arithmetic over the
chunk's air: 12,288 m^3 at 1,206 J/(m^3*K) is 14.8 MJ per degree, which makes one cloud +0.13 C
and a room full of them a couple of degrees. Capped per tick at `MAX_AMBIENT_STEP_C`.

§1 `duration=1.0s` IS COUNTED IN FRAMES, NOT SECONDS. `Reaction_Cooldown` expires at a MICRO-FRAME
deadline (`REACTION_COOLDOWN_FRAMES = 60`). A cooldown measured in scaled deltas would be six
times longer while bullet-time is held, which is a physics rule quietly depending on a viewer
setting. Expiry is stored on `ChemistryComponent.tag_expiry`, NOT in a system-side dictionary
keyed by row: `destroy_entity` clears every registry atomically, so a component field is cleaned
up with the entity and a system map would hand a recycled row the previous occupant's lock.

§2 `return null` IS NOT AN ERROR REPORT. The sketch prints to stdout and returns null, which from
the UI's seat is indistinguishable from a crash. `compile` returns `{ok, spell, reason}` and the
Grimoire prints the reason.

§2 THE TWO CAPS MUST FAIL DIFFERENTLY. Complexity REFUSES — it is a knowledge gate, and the player
can act on it. Geometry CLAMPS and records what it clamped in `caps_applied` — a 400 m radius is
not a knowledge problem, and refusing it would let a player author a spell they can never cast and
never learn why. The sketch's `rune.radius = 15.0` also mutated the RUNE, which is shared content:
the second caster would find the table permanently rewritten.

§2 CAP THE FINAL EXTENT, NOT THE STARTING RADIUS. An expanding aura reaches
`radius + expansion * ttl`, so clamping the initial radius alone leaves the cap defeatable by any
rune with an expansion rate.

§2 `Rune_Stability` HAD NO BOOTSTRAP VALUE, as an input audit noted and left to this sprint. At 0
the budget is 0 and nothing compiles, so the entire magic layer would have shipped built, tested,
and unreachable. Seeded at 10 in `MindComponent.seed_field_primer`, giving a budget of 15.

§3 `ECSManager.minds[ECSManager.player_handle()]` IS AN ADR-19 VIOLATION. Registries are keyed by
ROW; `player_handle()` returns a packed handle. Resolve first.

§3 TRIGGERS MUST DRIVE BEHAVIOUR. Written and read by nobody in the first implementation:
`trigger`, `delay_s`, and the Cone's angle all compiled, cost complexity, and changed nothing —
four trigger runes with identical behaviour and a cone that was a sphere. Now the TRIGGER decides
when the payload fires and the SHAPE decides where, which is what makes the magic doc's Trap
(proximity + aura) and its fireball (impact + projectile) different spells rather than the same
one. Multiple triggers resolve by precedence, not last-wins, because the doc's own standard
fireball carries two and last-wins would make behaviour depend on key-press order.

§3 PROJECTILES DO NOT GO THROUGH `CollisionResolveSystem`. That system slides a body along a wall
and steps it up a ledge, which is right for a person and wrong for a fireball — a spell that slid
along the wall it was aimed at would never detonate. `EphemeralSystem` advances them.

§4 `body.exposure[...] = 0.0` MUST RESET UNCONDITIONALLY. The sketch resets only after a successful
roll, so an entity already at `MAX_MUTATIONS` sits pinned at the threshold and re-enters the
mutation branch every tick, forever.

§4 `WorldGrid.chunks[current_chunk].has_tag(...)` — chunks had no tags. Added as
`ChunkData.hazard_tags` (registry §6), and exposure also accrues from the entity's OWN chemistry
tags, which is how wading through sludge works.

§4 EVERY MUTATION MUST CHANGE A NUMBER. A table of evocative tag names that alters nothing is this
codebase's signature defect and a mutation table is the ideal shape for it. Each entry carries its
stat deltas, and `test_mutation.gd` fails if one is added without any.

§5 THE MUTATION AFFINITY TABLE MUST NAME REAL CULTURES. Its first draft invented `CULTURE_FUNGAL`
and three siblings that no generated faction has ever carried, which would have made every
affinity branch unreachable and the whole mechanism a constant revulsion wearing a lookup table.
It now names tags from `DAGGenerator.CULTURES`, and an invariant test fails if the two drift.
