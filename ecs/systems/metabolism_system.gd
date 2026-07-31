## Needs and stamina on the Simulation tick.
##
## SIGN CONVENTIONS were undefined in the specs; both directions appeared in different docs.
## Canonical: hunger RISES toward 100, energy and morale FALL toward 0. This system also owns
## BodyComponent.stamina, including cold exposure, which the registry left orphaned.
class_name MetabolismSystem
extends RefCounted

## 2 Hz Simulation tick, and ADR-9 makes 1 in-game hour = 20 Simulation ticks. At 0.139/tick an
## NPC reaches the hunger interrupt in ~27 in-game hours and gains only +22 hunger across an
## 8-hour sleep block, which is survivable. A naive 1.0/tick would add +160 overnight and starve
## every NPC in the world every single night.
const HUNGER_PER_TICK: float = 0.139
const ENERGY_PER_TICK: float = 0.25
const SLEEP_RESTORE_PER_TICK: float = 0.50
const MEAL_HUNGER_RESTORE: float = 40.0

const IDEAL_TEMP_C: float = 20.0
const COLD_DRAIN_COEFFICIENT: float = 0.1
const BASE_STAMINA_DRAIN: float = 0.05

var entities_processed: int = 0
var starving_count: int = 0


func run(chunk: ChunkData) -> void:
	entities_processed = 0
	starving_count = 0
	var rows: PackedInt32Array = ECSManager.query(ComponentMask.NEEDS)
	for i in rows.size():
		var row: int = rows[i]
		var need: NeedsComponent = ECSManager.needs[row]
		var schedule: ScheduleComponent = ECSManager.schedules.get(row)
		var sleeping: bool = (
			schedule != null
			and schedule.block_for_hour(GameClock.hour) == ScheduleComponent.Block.SLEEP
		)

		need.hunger += HUNGER_PER_TICK
		if sleeping:
			need.energy += SLEEP_RESTORE_PER_TICK
		else:
			need.energy -= ENERGY_PER_TICK
		if need.hunger >= 100.0:
			starving_count += 1
			need.morale -= 0.5
		need.clamp_all()

		_drain_stamina(row, chunk)
		entities_processed += 1


## Stamina drain including environmental exposure. The cold term is why a torch or warm clothing
## is a real decision on a 5C floor.
func _drain_stamina(row: int, chunk: ChunkData) -> void:
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null:
		return
	var drain: float = BASE_STAMINA_DRAIN
	var deficit: float = IDEAL_TEMP_C - chunk.ambient_temperature_c
	if deficit > 0.0:
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		var insulated: bool = chemistry != null and chemistry.has_tag(&"Warm")
		if not insulated:
			drain += deficit * COLD_DRAIN_COEFFICIENT
			body.exposure[&"Cold"] = float(body.exposure.get(&"Cold", 0.0)) + deficit * 0.01
	body.stamina = clampf(body.stamina - drain, 0.0, body.max_stamina)


static func consume_meal(need: NeedsComponent) -> void:
	need.hunger = maxf(0.0, need.hunger - MEAL_HUNGER_RESTORE)
	need.morale = minf(100.0, need.morale + 5.0)


func counters() -> Dictionary:
	return {"metabolism_entities": entities_processed, "starving": starving_count}
