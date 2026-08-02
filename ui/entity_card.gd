## What a thing IS, in the player's words rather than the simulation's.
##
## THIS EXISTS BECAUSE THE ONLY WAY TO IDENTIFY ANYTHING WAS `Tab`, which dumps a raw component
## list into the debug panel. "creature #12" and "618 x MAT_CLOTH" are answers to a programmer's
## question. A player looking at a red box wants to know it is a rat, that it is on fire, and
## that it is nearly dead — and wants that without pressing a key or learning a tag vocabulary.
##
## PURE AND STATIC. It reads ECS state and returns strings; it never writes, never allocates a
## node, and never touches the scene tree. `HoverCard` renders it, `DebugOverlay` reuses it for
## the event feed, and a headless test can assert every line without a viewport.
##
## THE TAG VOCABULARY IS NOT THE PLAYER'S VOCABULARY. `active_tags` mixes three unrelated things:
## transient states the player caused (`Burning`), innate material properties that never change
## (`High_Conductivity`), and internal bookkeeping (`Reaction_Cooldown`). Only the first kind is
## news. `CONDITION_WORDS` is therefore an ALLOW-list, not a translation table with exclusions:
## a tag nobody wrote a player-facing word for is invisible here by default, which is the safe
## direction to fail.
class_name EntityCard
extends RefCounted

## Transient states worth telling the player about, in plain language. Anything absent from this
## map is deliberately not shown — see the class docstring.
const CONDITION_WORDS: Dictionary = {
	&"Burning": "on fire",
	&"Wet": "soaked",
	&"Slippery": "slippery",
	&"Spores": "spore-choked",
	&"Volatile_Gas": "venting gas",
	&"Filth": "filthy",
	&"Bleeding": "bleeding",
	&"Arcane_Burn": "arcane burns",
	&"Steam": "steaming",
	&"Smoke": "smoking",
	&"Explosion": "detonating",
	&"Inscribed": "inscribed with runes",
}

## Beast species to a word. `spawn_creature` took a species, branched on it for stats, and threw
## it away — so every animal in the build was "creature". `BodyComponent.species` now keeps it.
const SPECIES_WORDS: Dictionary = {
	&"SPC_CORPSE_RAT": "Rat",
	&"SPC_CITIZEN": "Villager",
}

## Given names, indexed by a hash of the entity HANDLE (row plus generation), so a recycled row
## becomes a different person rather than inheriting the dead one's name.
const GIVEN_NAMES: Array[String] = [
	"Kara", "Bren", "Odd", "Sena", "Marek", "Hilde", "Torv", "Juna", "Aldric", "Vesna",
	"Rurik", "Mira", "Halvor", "Ingrid", "Cass", "Dovan", "Elsa", "Fenn", "Greta", "Hask",
]

## Family names, drawn from the same place-name stems the chronicle uses, so a villager's name
## and their faction's name come from one world.
const FAMILY_NAMES: Array[String] = [
	"Karak", "Grimhold", "Ashfen", "Duskvale", "Ironmoor", "Blackreach", "Thornwick",
	"Greymarch", "Emberdeep", "Hollowfast",
]

const STATUS_WORDS: Dictionary = {
	ECSEnums.RelationshipStatus.WAR: "hostile to you",
	ECSEnums.RelationshipStatus.NEUTRAL: "indifferent to you",
	ECSEnums.RelationshipStatus.TRADE: "friendly to you",
	ECSEnums.RelationshipStatus.ALLIED: "an ally",
}

const STATUS_COLOURS: Dictionary = {
	ECSEnums.RelationshipStatus.WAR: UITheme.DANGER,
	ECSEnums.RelationshipStatus.NEUTRAL: UITheme.TEXT_MUTED,
	ECSEnums.RelationshipStatus.TRADE: UITheme.GOOD,
	ECSEnums.RelationshipStatus.ALLIED: UITheme.GOOD,
}

## Player words for what a compiled spell throws, looked up from its payload tags in order.
const SPELL_PAYLOAD_WORDS: Dictionary = {
	&"Burning": "fire",
	&"Wet": "water",
	&"Spores": "spore",
	&"Filth": "filth",
}

## Player words for how a compiled spell moves.
const SPELL_SHAPE_WORDS: Dictionary = {
	RuneLibrary.SHAPE_PROJECTILE: "bolt",
	RuneLibrary.SHAPE_AURA: "aura",
	RuneLibrary.SHAPE_CONE: "wave",
	RuneLibrary.SHAPE_SELF: "burst",
}

## Last known titles, keyed by FULL HANDLE, for naming things that no longer exist — a stack
## destroyed by a pickup merge, a corpse that burned away. Bounded; oldest entry evicted.
const MAX_REMEMBERED_TITLES: int = 256

## Below this fraction of max health, the health figure turns red rather than green.
const HURT_FRACTION: float = 0.35
const WOUNDED_FRACTION: float = 0.75

static var _remembered_titles: Dictionary = {}


## The headline. One short noun phrase, never an id.
static func title(row: int) -> String:
	if row == WorldConstants.PLAYER_INDEX:
		return "You"
	if _is_corpse(row):
		return "Remains of %s" % _lower_article(_living_noun(row))
	if _is_person(row):
		return person_name(row)
	if ECSManager.bodies.has(row):
		return _living_noun(row)
	if ECSManager.has_components(row, ComponentMask.FACTION_CORE):
		return _faction_name(row)
	return _item_title(row)


## The line under the title: what category of thing this is, plus its one defining fact.
static func kind_line(row: int) -> String:
	# Empty for the player: the title already says "You", and a second line reading "you" under
	# it is the card telling you nothing twice.
	if row == WorldConstants.PLAYER_INDEX:
		return ""
	if _is_corpse(row):
		return "corpse"
	if _is_person(row):
		return _person_kind(row)
	if ECSManager.bodies.has(row):
		return "beast"
	if ECSManager.has_components(row, ComponentMask.FACTION_CORE):
		return "faction"
	return "item"


## A stable, invented name for a villager. Derived from the HANDLE, so it survives as long as the
## entity does and changes when the row is reused by somebody else.
static func person_name(row: int) -> String:
	var handle: int = ECSManager.handle_of(row)
	var salt: int = absi(handle if handle != EH.INVALID else row)
	var given: String = GIVEN_NAMES[salt % GIVEN_NAMES.size()]
	var family: String = FAMILY_NAMES[(salt / GIVEN_NAMES.size()) % FAMILY_NAMES.size()]
	return "%s of %s" % [given, family]


## Plain-language transient states. Empty when there is nothing notable, which is the common case.
static func conditions(row: int) -> Array[String]:
	var out: Array[String] = []
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry != null:
		for tag in chemistry.active_tags:
			if CONDITION_WORDS.has(tag):
				out.append(String(CONDITION_WORDS[tag]))
	out.append_array(_needs_words(row))
	out.append_array(_mutation_words(row))
	return out


## Bars worth drawing: label, current, maximum. Health for anything with a body; stamina only
## when it can actually be spent, which today means the player.
static func vitals(row: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null or _is_corpse(row):
		return out
	out.append({"label": "Health", "value": body.health, "max": body.max_health})
	if row == WorldConstants.PLAYER_INDEX:
		out.append({
			"label": "Stamina", "value": body.stamina, "max": body.effective_max_stamina()
		})
	return out


## How this entity's faction regards the player, or an empty Dictionary when it has no faction.
static func standing(row: int) -> Dictionary:
	if row == WorldConstants.PLAYER_INDEX:
		return {}
	var identity: SocialIdentityComponent = ECSManager.social_identities.get(row)
	if identity == null or identity.faction_id < 0:
		return {}
	var core: FactionCoreComponent = DAGInstantiator.faction_core(identity.faction_id)
	if core == null:
		return {}
	var score: float = ReputationSystem.relationship_score(
		core, WorldConstants.PLAYER_FACTION_ID
	)
	var status: ECSEnums.RelationshipStatus = ReputationSystem.status_for(score)
	return {
		"text": String(STATUS_WORDS.get(status, "indifferent to you")),
		"colour": String(STATUS_COLOURS.get(status, UITheme.TEXT_MUTED)),
		"score": score,
	}


## Secondary facts: mass, worth, and temperature when it is worth remarking on.
static func facts(row: int) -> Array[String]:
	var out: Array[String] = []
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if physical == null:
		return out
	# Mass is shown for things you might pick up, throw, or burn — not for living people, where
	# "70.0 kg" is a fact about a person the player has no use for.
	var is_living_person: bool = _is_person(row) and not _is_corpse(row)
	if physical.mass_kg >= 0.005 and not is_living_person:
		out.append("%.1f kg" % physical.mass_kg)
	var temperature: float = physical.temperature_c()
	if temperature >= 60.0:
		out.append("%.0f C — hot" % temperature)
	elif temperature <= 0.0:
		out.append("%.0f C — freezing" % temperature)
	return out


## The colour a health figure should take, so "nearly dead" is visible without reading numbers.
static func vital_colour(value: float, maximum: float) -> String:
	if maximum <= 0.0:
		return UITheme.TEXT_MUTED
	var fraction: float = value / maximum
	if fraction <= HURT_FRACTION:
		return UITheme.DANGER
	if fraction <= WOUNDED_FRACTION:
		return UITheme.WARNING
	return UITheme.GOOD


## `title`, but works for the dead too. The interesting events are exactly the ones that end an
## entity — a merged stack, a burned corpse — so the last known name is remembered per HANDLE
## and returned once the entity is gone. Handle-keyed, never row-keyed: rows are recycled, and
## a row-keyed cache once attributed deaths to whatever now occupied the slot.
static func title_or_last(entity: int) -> String:
	var row: int = ECSManager.resolve(entity)
	if row < 0:
		return _remembered_titles.get(entity, "<gone>")
	var name: String = title(row)
	if _remembered_titles.size() >= MAX_REMEMBERED_TITLES:
		_remembered_titles.erase(_remembered_titles.keys()[0])
	_remembered_titles[entity] = name
	return name


## A compiled spell in the player's words. The id is the rune list joined with `+`, which is an
## implementation detail wearing a name badge — "Fire bolt" is what the keybar and the feed say.
static func spell_name(spell: CompiledSpell) -> String:
	var payload: String = ""
	for tag in spell.applies_tags:
		if SPELL_PAYLOAD_WORDS.has(tag):
			payload = String(SPELL_PAYLOAD_WORDS[tag])
			break
	if payload == "":
		if spell.removes_tags.has(&"Wet"):
			payload = "drying"
		elif spell.energy_j > 0.0:
			payload = "scalding"
		elif spell.energy_j < 0.0:
			payload = "chilling"
		else:
			payload = "arcane"
	var name: String = "%s %s" % [payload, String(SPELL_SHAPE_WORDS.get(spell.shape, "spell"))]
	if spell.unstable:
		name = "unstable " + name
	return name.substr(0, 1).to_upper() + name.substr(1)


static func _is_corpse(row: int) -> bool:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	return chemistry != null and chemistry.active_tags.has(&"Corpse")


## A person is anything that belongs to a faction. Beasts never do.
static func _is_person(row: int) -> bool:
	var identity: SocialIdentityComponent = ECSManager.social_identities.get(row)
	return identity != null and identity.faction_id >= 0


## What a body IS, ignoring whether it is currently alive.
static func _living_noun(row: int) -> String:
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body != null and SPECIES_WORDS.has(body.species):
		return String(SPECIES_WORDS[body.species])
	if _is_person(row):
		return "Villager"
	return "Creature"


## "Hauler, Human of Grimhold". Comma-joined rather than "Hauler OF Human of Grimhold" — faction
## names already contain "of", so the possessive form stutters.
static func _person_kind(row: int) -> String:
	var parts: Array[String] = []
	var profession: ProfessionComponent = ECSManager.professions.get(row)
	if profession != null and profession.profession != &"":
		parts.append(_profession_word(profession.profession))
	var faction: String = _faction_of_person(row)
	if faction != "":
		parts.append(faction)
	return "villager" if parts.is_empty() else ", ".join(parts)


static func _profession_word(profession: StringName) -> String:
	var raw: String = String(profession).trim_prefix("Prof_")
	return raw.capitalize()


static func _faction_of_person(row: int) -> String:
	var identity: SocialIdentityComponent = ECSManager.social_identities.get(row)
	if identity == null:
		return ""
	var core: FactionCoreComponent = DAGInstantiator.faction_core(identity.faction_id)
	return "" if core == null else _core_name(core)


static func _faction_name(row: int) -> String:
	var core: FactionCoreComponent = ECSManager.faction_cores.get(row)
	return "A faction" if core == null else _core_name(core)


## The DAG holds the prose name; the component holds only the id, so go and ask.
static func _core_name(core: FactionCoreComponent) -> String:
	if World.boot_report == null or World.boot_report.generator == null:
		return "faction %d" % core.faction_id
	var node: DAGNode = World.boot_report.generator.node_by_id(core.dag_node_id)
	return "faction %d" % core.faction_id if node == null else String(node.name)


## "5 Copper", or "Copper" when there is only one. The material and the count ARE the answer to
## "what is this"; `MAT_COPPER` is the answer to a different question.
static func _item_title(row: int) -> String:
	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if composition == null:
		return "Object"
	var word: String = material_word(composition.dominant_material())
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	var quantity: int = 1 if physical == null else physical.quantity
	return word if quantity <= 1 else "%d %s" % [quantity, word]


## `MAT_BIOMASS` reads as "Biomass". The prefix is storage detail and the player never asked.
static func material_word(material: StringName) -> String:
	var raw: String = String(material).trim_prefix("MAT_")
	return raw.capitalize()


## Needs the player can act on. Deliberately coarse — an exact hunger float is a debug fact.
static func _needs_words(row: int) -> Array[String]:
	var out: Array[String] = []
	var needs: NeedsComponent = ECSManager.needs.get(row)
	if needs == null or _is_corpse(row):
		return out
	if needs.hunger >= 80.0:
		out.append("starving")
	elif needs.hunger >= 55.0:
		out.append("hungry")
	if needs.energy <= 20.0:
		out.append("exhausted")
	return out


static func _mutation_words(row: int) -> Array[String]:
	var out: Array[String] = []
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null:
		return out
	for entry in body.mutations:
		var word: String = String(entry)
		if word.begins_with("Resist_"):
			continue
		out.append(word.replace("_", " ").to_lower())
	return out


## "a Rat" / "an Ogre". Only used inside "Remains of ...".
static func _lower_article(noun: String) -> String:
	var lowered: String = noun.to_lower()
	var article: String = "an" if "aeiou".contains(lowered.substr(0, 1)) else "a"
	return "%s %s" % [article, lowered]
