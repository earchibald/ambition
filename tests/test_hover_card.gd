## The player-facing hover card (`EntityCard` + `HoverCard.card_text`).
##
## The point of this feature is that a player can identify a thing WITHOUT learning the internal
## vocabulary, so every assertion here is about what the card does NOT say as much as what it
## does: no row numbers, no handles, no `MAT_` prefixes, no raw tag names.
extends GutTest

const SEED: int = 4242


func before_each() -> void:
	GameLoopManager.set_physics_process(false)
	World.boot_scenario(World.SCENARIO_TEST_ARENA, SEED)
	RNGService.reseed_all(SEED)


func after_all() -> void:
	GameLoopManager.set_physics_process(true)


func _row_of(handle: int) -> int:
	return ECSManager.resolve(handle)


func _here(offset: Vector3) -> Vector3:
	return ECSManager.position_of(WorldConstants.PLAYER_INDEX) + offset


## What the player actually reads: the card with every BBCode tag removed.
func _visible_text(bbcode: String) -> String:
	var regex := RegEx.new()
	regex.compile("\\[[^\\]]*\\]")
	return regex.sub(bbcode, "", true)


# --- Naming ------------------------------------------------------------------------------------


func test_a_rat_is_called_a_rat_not_a_creature_number() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	assert_eq(EntityCard.title(row), "Rat", "the species survives the spawn call")
	assert_eq(EntityCard.kind_line(row), "beast", "and it reads as an animal, not a villager")


## The species was previously taken as an argument, branched on, and thrown away — which is why
## every animal in the build displayed as "creature".
func test_the_species_is_actually_stored_on_the_body() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	assert_eq(ECSManager.bodies[row].species, &"SPC_CORPSE_RAT", "not discarded at spawn")


func test_an_item_is_named_by_material_and_count_without_the_storage_prefix() -> void:
	var handle: int = World.spawn_item(
		_here(Vector3(1.0, 0.0, 0.0)), MaterialLibrary.MAT_IRON, 100.0, 618
	)
	var title: String = EntityCard.title(_row_of(handle))
	assert_string_contains(title, "618", "the count is the first thing you want")
	assert_string_contains(title, "Iron", "and the material in a word")
	assert_false(title.contains("MAT_"), "the storage prefix never reaches the player")


func test_a_single_item_is_not_labelled_with_a_count_of_one() -> void:
	var handle: int = World.spawn_item(
		_here(Vector3(1.0, 0.0, 0.0)), MaterialLibrary.MAT_COPPER, 100.0, 1
	)
	assert_eq(EntityCard.title(_row_of(handle)), "Copper", "'1 Copper' reads as a bug")


func test_the_player_is_you() -> void:
	assert_eq(EntityCard.title(WorldConstants.PLAYER_INDEX), "You")


func test_a_corpse_is_named_for_what_it_used_to_be() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	ECSManager.chemistries[row].add_tag(&"Corpse")
	assert_eq(EntityCard.title(row), "Remains of a rat", "not 'corpse #12'")
	assert_eq(EntityCard.kind_line(row), "corpse")


## Rows are recycled off the free list, so a name derived from the row alone would hand a dead
## villager's identity to whatever spawns into their slot next.
func test_a_recycled_row_becomes_a_different_person() -> void:
	var first: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(first)
	var before: String = EntityCard.person_name(row)
	ECSManager.destroy_entity(first)
	var second: int = ECSManager.allocate_entity()
	assert_eq(EH.index_of(second), row, "the row really was reused")
	assert_ne(EntityCard.person_name(row), before, "and the name did not come with it")


func test_a_persons_name_is_stable_while_they_live() -> void:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	assert_eq(
		EntityCard.person_name(row), EntityCard.person_name(row), "asking twice is not a reroll"
	)


# --- Conditions, in the player's words ---------------------------------------------------------


func test_tags_are_translated_not_printed() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	ECSManager.chemistries[row].add_tag(&"Burning")
	ECSManager.chemistries[row].add_tag(&"Wet")
	var words: Array[String] = EntityCard.conditions(row)
	assert_true(words.has("on fire"), "Burning reads as on fire: %s" % str(words))
	assert_true(words.has("soaked"), "Wet reads as soaked: %s" % str(words))
	assert_false(words.has("Burning"), "the raw tag never reaches the player")


## `active_tags` mixes player-visible states with innate material properties and internal
## bookkeeping. Showing all of them is the "overwhelmed by the tagging system" complaint.
func test_internal_and_innate_tags_are_not_shown() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	var chemistry: ChemistryComponent = ECSManager.chemistries[row]
	chemistry.add_tag(&"Reaction_Cooldown")
	chemistry.add_tag(&"High_Conductivity")
	chemistry.add_tag(&"Adventurer_Remains")
	assert_eq(EntityCard.conditions(row), [] as Array[String], "none of these are news")


func test_hunger_is_a_word_not_a_float() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	ECSManager.needs[row].hunger = 90.0
	assert_true(EntityCard.conditions(row).has("starving"), "90.0 means nothing to a player")


# --- Vitals ------------------------------------------------------------------------------------


func test_a_wounded_creature_reports_health_and_turns_red() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	var body: BodyComponent = ECSManager.bodies[row]
	body.health = body.max_health * 0.2
	var vitals: Array[Dictionary] = EntityCard.vitals(row)
	assert_eq(vitals.size(), 1, "a beast shows health and nothing else")
	assert_eq(
		EntityCard.vital_colour(body.health, body.max_health),
		PanelFormat.BAD,
		"nearly dead is visible without reading the number"
	)
	assert_eq(
		EntityCard.vital_colour(body.max_health, body.max_health),
		PanelFormat.GOOD,
		"and unhurt is not"
	)


func test_a_corpse_has_no_health_bar() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	ECSManager.chemistries[row].add_tag(&"Corpse")
	assert_eq(EntityCard.vitals(row), [] as Array[Dictionary], "a dead thing has no vitals")


func test_the_player_card_shows_stamina_as_well() -> void:
	var vitals: Array[Dictionary] = EntityCard.vitals(WorldConstants.PLAYER_INDEX)
	assert_eq(vitals.size(), 2, "your own card is the one place stamina matters")
	assert_eq(String(vitals[1]["label"]), "Stamina")


# --- The rendered card -------------------------------------------------------------------------


func test_the_card_never_leaks_ids_or_masks() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	ECSManager.bodies[row].health = 3.0
	var text: String = HoverCard.card_text(row)
	assert_string_contains(text, "Rat", "it says what the thing is")
	assert_string_contains(text, "3/8", "and how hurt it is")
	# Asserted against the VISIBLE text. The markup legitimately contains '#' in every colour
	# code, so scanning the raw BBCode tests the wrong string — this is what the player reads.
	var visible: String = _visible_text(text)
	for leak in ["#", "e0:g", "MAT_", "ComponentMask"]:
		assert_false(
			visible.contains(leak), "no '%s' in a player-facing card: %s" % [leak, visible]
		)


func test_an_entity_with_no_faction_gets_no_standing_line() -> void:
	var row: int = _row_of(World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0))))
	assert_eq(EntityCard.standing(row), {}, "a rat has no opinion of you")


## The card is read every frame from `_process`, so it must survive the frame in which its
## subject stops existing rather than throwing on a half-freed row.
func test_the_card_survives_a_target_that_just_died() -> void:
	var handle: int = World.spawn_creature(_here(Vector3(2.0, 0.0, 0.0)))
	var row: int = _row_of(handle)
	ECSManager.destroy_entity(handle)
	ECSManager.flush_structural_changes()
	assert_eq(ECSManager.resolve(handle), -1, "it really is gone")
	# The renderer guards on `resolve` before calling in; this asserts the words layer is total
	# anyway, because a tooltip that crashes on a dying target is worse than one that lags.
	assert_ne(EntityCard.title(row), "", "still answers rather than throwing")
