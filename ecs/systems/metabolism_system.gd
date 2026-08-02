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

## REST. Nothing in the build restored stamina — not sleep, not meals, not standing still — so
## every body in the world ground monotonically to zero, and casting Strain was unrecoverable.
## Standing still is resting: stamina refills toward the strain-reduced ceiling, and Strain
## itself heals at half that rate, so a drained caster is ~80 s of standing from a clear head.
## "Rest in a safe zone" (magic doc §2) is read as "rest"; a safe-zone distinction is recorded
## as not built.
const REST_STAMINA_PER_TICK: float = 0.5
const REST_STRAIN_PER_TICK: float = 0.25
const RESTING_SPEED_MPS: float = 0.05

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
## is a real decision on a 5C floor. A body at rest RECOVERS instead: standing still is the
## universal rest action, available to the player and to NPCs alike.
func _drain_stamina(row: int, chunk: ChunkData) -> void:
	var body: BodyComponent = ECSManager.bodies.get(row)
	if body == null:
		return
	var resting: bool = (
		ECSManager.has_components(row, ComponentMask.POSITION)
		and ECSManager.velocity_of(row).length() <= RESTING_SPEED_MPS
	)
	var drain: float = BASE_STAMINA_DRAIN
	var deficit: float = IDEAL_TEMP_C - chunk.ambient_temperature_c
	if deficit > 0.0:
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		var insulated: bool = chemistry != null and chemistry.has_tag(&"Warm")
		if not insulated:
			drain += deficit * COLD_DRAIN_COEFFICIENT
			body.exposure[&"Cold"] = float(body.exposure.get(&"Cold", 0.0)) + deficit * 0.01
			resting = false
	if resting:
		# Trauma tags from magic mishaps cripple recovery (the Mercy Cap's price): an
		# Arcane_Burn quarters the rest rate and stops strain healing entirely until cured.
		var chemistry: ChemistryComponent = ECSManager.chemistries.get(row)
		var burned: bool = chemistry != null and chemistry.has_tag(&"Arcane_Burn")
		if not burned:
			body.strain = maxf(0.0, body.strain - REST_STRAIN_PER_TICK)
		var rate: float = REST_STAMINA_PER_TICK * (0.25 if burned else 1.0)
		body.stamina = clampf(body.stamina + rate, 0.0, body.effective_max_stamina())
		return
	body.stamina = clampf(body.stamina - drain, 0.0, body.effective_max_stamina())


static func consume_meal(need: NeedsComponent) -> void:
	need.hunger = maxf(0.0, need.hunger - MEAL_HUNGER_RESTORE)
	need.morale = minf(100.0, need.morale + 5.0)


func counters() -> Dictionary:
	return {"metabolism_entities": entities_processed, "starving": starving_count}
