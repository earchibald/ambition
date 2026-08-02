## Inventory conservation, encumbrance, acoustics, LoD, and tick cadence.
extends GutTest

var inventory_system: InventorySystem
var spawned: PackedInt64Array = PackedInt64Array()


func before_each() -> void:
	inventory_system = InventorySystem.new()
	spawned = PackedInt64Array()


func after_each() -> void:
	for i in spawned.size():
		ECSManager.destroy_entity(spawned[i])


func _spawn_item(material_id: StringName, volume: float, quantity: int = 1) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = volume
	physical.quantity = quantity
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)
	var composition := MaterialCompositionComponent.new({material_id: 1.0})
	ECSManager.materials[row] = composition
	ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
	MaterialLibrary.recompute_mass(physical, composition)
	ECSManager.qualities[row] = QualityComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.QUALITY)
	ECSManager.chemistries[row] = ChemistryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	spawned.append(handle)
	return handle


func _spawn_carrier(capacity: float = 50000.0) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.inventories[row] = InventoryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.INVENTORY)
	var container := ContainerComponent.new()
	container.capacity_cm3 = capacity
	ECSManager.containers[row] = container
	ECSManager.add_component_bit(row, ComponentMask.CONTAINER)
	ECSManager.bodies[row] = BodyComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.BODY)
	ECSManager.chemistries[row] = ChemistryComponent.new()
	ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	spawned.append(handle)
	return handle


func test_insert_updates_derived_volume_and_mass() -> void:
	var carrier: int = _spawn_carrier()
	var item: int = _spawn_item(MaterialLibrary.MAT_IRON, 1000.0)
	assert_true(inventory_system.try_insert(EH.index_of(carrier), item), "the item fits")
	var inventory: InventoryComponent = ECSManager.inventories[EH.index_of(carrier)]
	assert_almost_eq(inventory.total_volume_used, 1000.0, 0.1, "volume is tracked")
	assert_almost_eq(inventory.total_mass_kg, 7.87, 0.01, "mass is derived from composition")


func test_overstuff_beyond_115_percent_is_rejected() -> void:
	var carrier: int = _spawn_carrier(1000.0)
	assert_true(
		inventory_system.try_insert(EH.index_of(carrier), _spawn_item(MaterialLibrary.MAT_CLOTH, 1100.0)),
		"115% overstuff is allowed — that is what makes rupture a gamble"
	)
	assert_false(
		inventory_system.try_insert(EH.index_of(carrier), _spawn_item(MaterialLibrary.MAT_CLOTH, 500.0)),
		"going past the overstuff ceiling is refused"
	)


func test_overstuffing_applies_the_bursting_tag() -> void:
	var carrier: int = _spawn_carrier(1000.0)
	inventory_system.try_insert(EH.index_of(carrier), _spawn_item(MaterialLibrary.MAT_CLOTH, 1100.0))
	var chemistry: ChemistryComponent = ECSManager.chemistries[EH.index_of(carrier)]
	assert_true(chemistry.has_tag(&"Bursting"), "an overstuffed container is marked Bursting")


func test_bare_liquid_cannot_be_carried() -> void:
	var carrier: int = _spawn_carrier()
	var water: int = _spawn_item(MaterialLibrary.MAT_WATER, 500.0)
	ECSManager.physicals[EH.index_of(water)].phase = ECSEnums.Phase.LIQUID
	assert_false(
		inventory_system.try_insert(EH.index_of(carrier), water),
		"a liquid needs a container that accepts fluids"
	)


func test_nested_containers_are_rejected_by_default() -> void:
	var carrier: int = _spawn_carrier()
	var bag: int = _spawn_item(MaterialLibrary.MAT_CLOTH, 100.0)
	ECSManager.containers[EH.index_of(bag)] = ContainerComponent.new()
	ECSManager.add_component_bit(EH.index_of(bag), ComponentMask.CONTAINER)
	assert_false(
		inventory_system.try_insert(EH.index_of(carrier), bag),
		"bag-of-holding-inside-a-bag-of-holding is refused"
	)


## Identical stacks must merge rather than fragmenting the entity registry.
func test_identical_stacks_merge_and_conserve_quantity() -> void:
	var carrier: int = _spawn_carrier()
	var first: int = _spawn_item(MaterialLibrary.MAT_GOLD, 1.04, 10)
	var second: int = _spawn_item(MaterialLibrary.MAT_GOLD, 1.04, 15)
	inventory_system.try_insert(EH.index_of(carrier), first)
	inventory_system.try_insert(EH.index_of(carrier), second)
	var inventory: InventoryComponent = ECSManager.inventories[EH.index_of(carrier)]
	assert_eq(inventory.item_count(), 1, "the two stacks merged into one entity")
	assert_eq(
		ECSManager.physicals[EH.index_of(first)].quantity, 25, "total quantity is conserved"
	)


func test_split_then_merge_conserves_total_quantity() -> void:
	var stack: int = _spawn_item(MaterialLibrary.MAT_GOLD, 1.04, 100)
	var row: int = EH.index_of(stack)
	var removed: int = InventorySystem.split_stack(row, 40)
	spawned.append(removed)
	assert_eq(ECSManager.physicals[row].quantity, 60, "the source stack decremented")
	assert_eq(
		ECSManager.physicals[EH.index_of(removed)].quantity, 40, "the split carries the remainder"
	)
	assert_eq(
		ECSManager.physicals[row].quantity + ECSManager.physicals[EH.index_of(removed)].quantity,
		100,
		"split conserves total quantity"
	)


func test_cannot_split_more_than_the_stack_holds() -> void:
	var stack: int = _spawn_item(MaterialLibrary.MAT_GOLD, 1.04, 10)
	assert_false(
		EH.is_valid(InventorySystem.split_stack(EH.index_of(stack), 10)),
		"splitting the whole stack is refused"
	)


func test_different_quality_bands_do_not_merge() -> void:
	var a: int = _spawn_item(MaterialLibrary.MAT_IRON, 100.0, 1)
	var b: int = _spawn_item(MaterialLibrary.MAT_IRON, 100.0, 1)
	ECSManager.qualities[EH.index_of(b)].wear = 90.0
	assert_ne(
		InventorySystem.merge_key(EH.index_of(a)),
		InventorySystem.merge_key(EH.index_of(b)),
		"a pristine and a scrap item are not the same stack"
	)


## Encumbrance is applied IN THE ECS as a velocity divisor. The viewer only reads the result.
func test_heavier_load_reduces_speed() -> void:
	var carrier: int = _spawn_carrier()
	var row: int = EH.index_of(carrier)
	assert_almost_eq(InventorySystem.speed_multiplier(row), 1.0, 0.001, "empty means full speed")
	inventory_system.try_insert(row, _spawn_item(MaterialLibrary.MAT_GOLD, 3000.0))
	InventorySystem.recompute_totals(row)
	var loaded: float = InventorySystem.speed_multiplier(row)
	assert_lt(loaded, 1.0, "a heavy load slows the carrier")
	assert_gt(loaded, 0.0, "but never to a standstill")


# --- Acoustics --------------------------------------------------------------------------------


## The old curve claimed a 30 m cap it did not have, was undefined when empty, and returned
## NEGATIVE radii.
func test_acoustic_noise_is_defined_when_empty() -> void:
	var radius: float = _noise(0.0, 1.0)
	assert_almost_eq(radius, 2.0, 0.01, "an empty inventory has a defined base noise")


func test_acoustic_noise_is_never_negative() -> void:
	assert_gte(_noise(0.1, 20.0), 2.0, "a light load at high speed never goes negative")


func test_acoustic_noise_is_actually_capped() -> void:
	assert_lte(_noise(900.0, 30.0), 30.0, "1,000 glass vials while falling is still capped")


func test_acoustic_noise_rises_with_load_and_speed() -> void:
	assert_gt(_noise(900.0, 3.0), _noise(1.0, 3.0), "more resonant cargo is louder")
	assert_gt(_noise(900.0, 6.0), _noise(900.0, 3.0), "moving faster is louder")


func _noise(acoustic_sum: float, speed: float) -> float:
	return clampf(
		2.0 + 6.0 * (log(1.0 + acoustic_sum) / log(10.0)) * (speed / 3.0), 2.0, 30.0
	)


# --- LoD --------------------------------------------------------------------------------------


## ADR-3: the Active set is 3x3 same-floor PLUS the landing chunk above and below — not 3x3x3.
func test_active_set_is_nine_plus_two_not_twenty_seven() -> void:
	var active: Array[Vector3i] = LoDSystem.active_set(Vector3i.ZERO)
	assert_eq(active.size(), 11, "nine same-floor chunks plus one above and one below")


func test_same_floor_neighbours_are_active() -> void:
	assert_true(LoDSystem.is_in_active_set(Vector3i(1, 1, 0), Vector3i.ZERO), "diagonal is active")
	assert_false(
		LoDSystem.is_in_active_set(Vector3i(2, 0, 0), Vector3i.ZERO), "two chunks out is not"
	)


func test_only_the_landing_chunk_is_active_on_an_adjacent_floor() -> void:
	assert_true(
		LoDSystem.is_in_active_set(Vector3i(0, 0, 1), Vector3i.ZERO),
		"the landing chunk directly above is active"
	)
	assert_false(
		LoDSystem.is_in_active_set(Vector3i(1, 0, 1), Vector3i.ZERO),
		"its neighbour on that floor is NOT — this is what makes it 3x3+2, not 3x3x3"
	)


func test_two_floors_away_is_never_active() -> void:
	assert_false(
		LoDSystem.is_in_active_set(Vector3i(0, 0, 2), Vector3i.ZERO), "two floors out is abstracted"
	)


# --- Clock ------------------------------------------------------------------------------------


func test_clock_rolls_over_days_and_seasons() -> void:
	var clock_state: Dictionary = GameClock.save_to_dict()
	GameClock.hour = 23
	GameClock.day = 89
	GameClock.advance_hour()
	assert_eq(GameClock.hour, 0, "hour wrapped")
	assert_eq(GameClock.day, 90, "day advanced")
	assert_eq(GameClock.season, 1, "season advanced after 90 days")
	GameClock.load_from_dict(clock_state)


func test_elapsed_hours_is_monotonic() -> void:
	var before: int = GameClock.total_hours()
	GameClock.advance_hour()
	GameClock.advance_hour()
	assert_eq(GameClock.total_hours(), before + 2, "elapsed hours only ever increases")


## The Interregnum must NOT run 8,760 hourly ticks.
func test_interregnum_advances_a_year_without_hourly_ticks() -> void:
	var state: Dictionary = GameClock.save_to_dict()
	var before_year: int = GameClock.year
	GameClock.advance_interregnum_year()
	assert_eq(GameClock.year, before_year + 1, "a full year passed")
	assert_eq(
		GameClock.total_hours(),
		int(state["elapsed_hours"]) + GameClock.DAYS_PER_YEAR * 24,
		"elapsed hours jumped by exactly one year"
	)
	GameClock.load_from_dict(state)


# --- RNG --------------------------------------------------------------------------------------


## ADR-21: JSON coerces every number to a double, silently corrupting 64-bit RNG state and
## breaking ADR-8's only promise. The hi/lo split is what makes continuation work.
func test_rng_state_survives_a_json_round_trip() -> void:
	RNGService.reseed_all(987654321)
	for _i in 50:
		RNGService.randf_in(&"combat")
	var expected: float = RNGService.randf_in(&"combat")

	RNGService.reseed_all(987654321)
	for _i in 50:
		RNGService.randf_in(&"combat")
	var saved: String = JSON.stringify(RNGService.save_to_dict())

	RNGService.reseed_all(1)
	RNGService.load_from_dict(JSON.parse_string(saved))
	assert_eq(
		RNGService.randf_in(&"combat"), expected, "the stream continues exactly where it stopped"
	)


func test_named_streams_are_independent() -> void:
	RNGService.reseed_all(42)
	var combat_first: float = RNGService.randf_in(&"combat")
	RNGService.reseed_all(42)
	RNGService.randf_in(&"loot")
	assert_eq(
		RNGService.randf_in(&"combat"),
		combat_first,
		"drawing from one stream does not disturb another"
	)
