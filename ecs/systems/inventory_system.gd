## Physical carrying: volume limits, derived mass, and encumbrance.
##
## Mass affects movement through a divisor applied IN THE ECS. The viewer only reads the
## resulting position.
class_name InventorySystem
extends RefCounted

var moves_rejected: int = 0
## Why the last insertion was refused, in words a player can act on. "It will not fit" is not
## feedback; "40.0 L each, only 7.5 L free" is.
var last_rejection: StringName = &""
var stacks_merged: int = 0


## Recomputes cached totals from the actual contents. Never trust an incrementally-maintained
## total: a single missed update silently corrupts encumbrance forever.
static func recompute_totals(row: int) -> void:
	var inventory: InventoryComponent = ECSManager.inventories.get(row)
	if inventory == null:
		return
	var volume: float = 0.0
	var mass: float = 0.0
	for i in inventory.held_items.size():
		var item_row: int = ECSManager.resolve(inventory.held_items[i])
		if item_row < 0:
			continue
		var physical: PhysicalPropertyComponent = ECSManager.physicals.get(item_row)
		if physical == null:
			continue
		volume += physical.stack_volume_cm3()
		mass += physical.stack_mass_kg()
	inventory.total_volume_used = volume
	inventory.total_mass_kg = mass


## ADR-18 movement law. Encumbrance only bites past half of carry capacity, so a light load is
## free and a heavy one is a real decision.
static func speed_multiplier(row: int) -> float:
	var body: BodyComponent = ECSManager.bodies.get(row)
	var inventory: InventoryComponent = ECSManager.inventories.get(row)
	if body == null or inventory == null:
		return 1.0
	var capacity: float = body.carry_capacity_kg()
	var over: float = maxf(0.0, inventory.total_mass_kg - 0.5 * capacity)
	return 1.0 / (1.0 + over / maxf(capacity, 0.001))


## Attempts to put an item into a container. Enforces volume, filters, and nesting.
func try_insert(container_row: int, item_handle: int) -> bool:
	var item_row: int = ECSManager.resolve(item_handle)
	if item_row < 0:
		return false
	var inventory: InventoryComponent = ECSManager.inventories.get(container_row)
	var container: ContainerComponent = ECSManager.containers.get(container_row)
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(item_row)
	if not _may_accept(item_row, inventory, container, physical):
		return false

	# PARTIAL PICKUP. A village stockpile is a single stack of several hundred units — 400 iron
	# at 100 cm3 each is 40 litres — and a backpack holds 50. Whole-stack-or-nothing therefore
	# meant that in a generated world NOTHING could ever be picked up, and the only feedback was
	# "it will not fit". Taking a handful off a pile is the obvious real behaviour.
	var free_cm3: float = container.overstuff_limit_cm3() - inventory.total_volume_used
	var unit_cm3: float = maxf(physical.volume_cm3, 0.0001)
	var fits: int = int(floor(free_cm3 / unit_cm3))
	if fits <= 0:
		last_rejection = StringName(
			"%.1f L each, only %.1f L free" % [unit_cm3 / 1000.0, maxf(free_cm3, 0.0) / 1000.0]
		)
		moves_rejected += 1
		return false
	if fits < physical.quantity:
		_take_partial(container_row, item_row, physical, fits)
		return true

	if _try_merge(inventory, item_row, physical):
		ECSManager.destroy_entity(item_handle)
		stacks_merged += 1
		recompute_totals(container_row)
		return true

	inventory.add(item_handle)
	_leave_the_world(item_row)
	recompute_totals(container_row)
	_update_bursting(container_row, inventory, container)
	return true


## Null checks and tag/phase filters, folded together so `try_insert` keeps a readable shape.
func _may_accept(
	item_row: int,
	inventory: InventoryComponent,
	container: ContainerComponent,
	physical: PhysicalPropertyComponent
) -> bool:
	if inventory == null or container == null or physical == null:
		return false
	if _passes_filters(item_row, container, physical):
		return true
	last_rejection = &"this container refuses it"
	moves_rejected += 1
	return false


## Takes `count` units off a larger pile, leaving the rest on the ground.
##
## Merges into a matching stack when one is already held, so repeatedly scooping from the same
## pile produces one growing stack rather than a pocketful of fragments.
func _take_partial(
	container_row: int, item_row: int, physical: PhysicalPropertyComponent, count: int
) -> void:
	physical.quantity -= count
	MaterialLibrary.recompute_mass(physical, ECSManager.materials.get(item_row))

	var inventory: InventoryComponent = ECSManager.inventories[container_row]
	var key: String = merge_key(item_row)
	for handle in inventory.held_items:
		var held_row: int = ECSManager.resolve(handle)
		if held_row < 0 or merge_key(held_row) != key:
			continue
		var held: PhysicalPropertyComponent = ECSManager.physicals.get(held_row)
		if held == null:
			continue
		held.quantity += count
		MaterialLibrary.recompute_mass(held, ECSManager.materials.get(held_row))
		stacks_merged += 1
		recompute_totals(container_row)
		return

	inventory.add(ECSManager.handle_of(_clone_stack(item_row, count)))
	recompute_totals(container_row)
	_update_bursting(container_row, inventory, ECSManager.containers[container_row])


## A copy of a stack carrying `count` units, with NO position — it is born already in a pocket.
func _clone_stack(source_row: int, count: int) -> int:
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	var source: PhysicalPropertyComponent = ECSManager.physicals[source_row]

	var physical := PhysicalPropertyComponent.new()
	physical.volume_cm3 = source.volume_cm3
	physical.quantity = count
	physical.set_temperature_c(source.temperature_c())
	ECSManager.physicals[row] = physical
	ECSManager.add_component_bit(row, ComponentMask.PHYSICAL)

	var source_material: MaterialCompositionComponent = ECSManager.materials.get(source_row)
	if source_material != null:
		ECSManager.materials[row] = MaterialCompositionComponent.new(
			source_material.volume_fractions.duplicate()
		)
		ECSManager.add_component_bit(row, ComponentMask.MATERIAL)
		MaterialLibrary.recompute_mass(physical, ECSManager.materials[row])

	# Ownership and policy come along, or a scooped handful would launder itself out of the
	# faction's books and break the LoD conservation invariant.
	var source_owner: OwnershipComponent = ECSManager.ownerships.get(source_row)
	if source_owner != null:
		ECSManager.ownerships[row] = OwnershipComponent.new(source_owner.faction_id)
		ECSManager.add_component_bit(row, ComponentMask.OWNERSHIP)
	var source_policy: MaterializationComponent = ECSManager.materializations.get(source_row)
	if source_policy != null:
		var policy := MaterializationComponent.new()
		policy.policy = source_policy.policy
		policy.item_class = source_policy.item_class
		ECSManager.materializations[row] = policy
		ECSManager.add_component_bit(row, ComponentMask.MATERIALIZATION)

	var source_chemistry: ChemistryComponent = ECSManager.chemistries.get(source_row)
	if source_chemistry != null:
		var chemistry := ChemistryComponent.new()
		for tag in source_chemistry.active_tags:
			chemistry.add_tag(tag)
		ECSManager.chemistries[row] = chemistry
		ECSManager.add_component_bit(row, ComponentMask.CHEMISTRY)
	return row


## A carried item is no longer AT anywhere. Stripping POSITION removes it from the spatial hash,
## from every world query, and from the renderer.
##
## Without this a picked-up item stayed on the floor: still drawn, still in the hash, still within
## reach. Pressing take a second time then found it again and `_try_merge` merged the item INTO
## ITSELF — the entity was already in `held_items`, so it matched its own merge key, doubled its
## own quantity, and was then destroyed, leaving a dead handle in the inventory. A duplication bug
## reported as "you picked up <gone>".
func _leave_the_world(item_row: int) -> void:
	ECSManager.remove_component_bit(item_row, ComponentMask.POSITION)
	ECSManager.remove_component_bit(item_row, ComponentMask.LOOSE_ITEM)
	ECSManager.loose_items.erase(item_row)


## Tag filters, nesting, phase, and the overstuff ceiling.
func _passes_filters(
	item_row: int, container: ContainerComponent, physical: PhysicalPropertyComponent
) -> bool:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(item_row)
	var tags: Array[StringName] = [] if chemistry == null else chemistry.active_tags
	if not container.accepts(tags, ECSManager.containers.has(item_row)):
		return false
	# Liquids cannot exist bare in an inventory; they need a container that accepts them.
	if physical.phase == ECSEnums.Phase.LIQUID and not tags.has(&"Fluid_Container"):
		return false
	# VOLUME IS DELIBERATELY NOT CHECKED HERE. It used to be, and it rejected the WHOLE stack
	# before the caller could take a handful off it — which is why nothing in a generated
	# village could be picked up. Capacity is now the caller's decision, since only the caller
	# knows that a partial take is acceptable. Overstuff to 115% still applies there, which is
	# what makes rupture a gamble rather than a wall.
	return true


## Auto-merge on pickup: same material, quality, and tags stack instead of fragmenting memory.
func _try_merge(
	inventory: InventoryComponent, item_row: int, physical: PhysicalPropertyComponent
) -> bool:
	var key: String = merge_key(item_row)
	if key == "":
		return false
	for i in inventory.held_items.size():
		var existing_row: int = ECSManager.resolve(inventory.held_items[i])
		if existing_row < 0:
			continue
		# Never merge an item with itself. It matches its own key perfectly, so without this the
		# stack absorbs its own quantity and the entity is then destroyed out from under the
		# inventory that holds it.
		if existing_row == item_row:
			continue
		if merge_key(existing_row) != key:
			continue
		var existing: PhysicalPropertyComponent = ECSManager.physicals.get(existing_row)
		if existing == null:
			continue
		existing.quantity += physical.quantity
		return true
	return false


## Stacks merge only when material, quality band, and tags all match.
static func merge_key(row: int) -> String:
	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if composition == null:
		return ""
	var quality: QualityComponent = ECSManager.qualities.get(row)
	var band: int = 0 if quality == null else int(quality.condition())
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	var tags: Array = [] if chemistry == null else chemistry.active_tags.duplicate()
	tags.sort()
	return "%s|%d|%s" % [composition.dominant_material(), band, ",".join(tags)]


## Splitting a stack: decrement the source and spawn the removed quantity as a new entity.
static func split_stack(row: int, amount: int) -> int:
	var physical: PhysicalPropertyComponent = ECSManager.physicals.get(row)
	if physical == null or amount <= 0 or amount >= physical.quantity:
		return EH.INVALID
	physical.quantity -= amount

	var handle: int = ECSManager.allocate_entity()
	var new_row: int = EH.index_of(handle)
	var copy := PhysicalPropertyComponent.new()
	copy.quantity = amount
	copy.volume_cm3 = physical.volume_cm3
	copy.mass_kg = physical.mass_kg
	copy.heat_capacity = physical.heat_capacity
	copy.phase = physical.phase
	copy.set_temperature_c(physical.temperature_c())
	ECSManager.physicals[new_row] = copy
	ECSManager.add_component_bit(new_row, ComponentMask.PHYSICAL)

	var composition: MaterialCompositionComponent = ECSManager.materials.get(row)
	if composition != null:
		ECSManager.materials[new_row] = MaterialCompositionComponent.new(
			composition.volume_fractions
		)
		ECSManager.add_component_bit(new_row, ComponentMask.MATERIAL)
	ECSManager.set_position(new_row, ECSManager.position_of(row))
	ECSManager.add_component_bit(new_row, ComponentMask.POSITION)
	return handle


func _update_bursting(
	row: int, inventory: InventoryComponent, container: ContainerComponent
) -> void:
	var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
	if chemistry == null:
		return
	if inventory.total_volume_used > container.capacity_cm3:
		chemistry.add_tag(&"Bursting")
	else:
		chemistry.remove_tag(&"Bursting")


func counters() -> Dictionary:
	return {"inventory_rejected": moves_rejected, "stacks_merged": stacks_merged}
