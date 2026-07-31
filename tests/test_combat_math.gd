## Sprint 1 section 10 kinetic-energy combat model.
##
## Every assertion here is a worked number from the review that replaced the old formula, which
## was dimensionally broken five ways and dealt exactly zero damage from a standing attacker.
extends GutTest

const SWORD_KG: float = 1.5
const HUMAN_KG: float = 70.0
const RAT_KG: float = 0.4


func _human_body() -> BodyComponent:
	var body := BodyComponent.new()
	body.strength = 10.0
	body.structural_toughness = 1.0
	return body


## THE REGRESSION GUARD. The old model used the attacker's BODY velocity, so a stationary
## player dealt zero and Sprint 1 Step 6's own success state was unreachable.
func test_stationary_attacker_still_deals_damage() -> void:
	var body: BodyComponent = _human_body()
	var speed: float = ActionResolutionSystem.swing_speed(body, Vector3.ZERO, Vector3.FORWARD)
	var energy: float = ActionResolutionSystem.impact_energy(HUMAN_KG, SWORD_KG, speed)
	assert_gt(speed, 0.0, "swing speed is independent of body velocity")
	assert_almost_eq(energy, 106.25, 1.0, "a standing swing delivers ~106 J")


func test_moving_forward_adds_a_capped_charge_bonus() -> void:
	var body: BodyComponent = _human_body()
	var still: float = ActionResolutionSystem.swing_speed(body, Vector3.ZERO, Vector3.FORWARD)
	var charging: float = ActionResolutionSystem.swing_speed(
		body, Vector3.FORWARD * 4.0, Vector3.FORWARD
	)
	assert_gt(charging, still, "a forward lunge hits harder")
	assert_lte(charging, still * 1.5, "the charge bonus is capped at +50%")


func test_backpedalling_does_not_add_damage() -> void:
	var body: BodyComponent = _human_body()
	var still: float = ActionResolutionSystem.swing_speed(body, Vector3.ZERO, Vector3.FORWARD)
	var retreating: float = ActionResolutionSystem.swing_speed(
		body, Vector3.BACK * 5.0, Vector3.FORWARD
	)
	assert_eq(retreating, still, "moving away from the target adds nothing")


func test_stronger_attacker_hits_harder() -> void:
	var weak: BodyComponent = _human_body()
	var strong: BodyComponent = _human_body()
	strong.strength = 40.0
	var weak_e: float = ActionResolutionSystem.impact_energy(
		HUMAN_KG, SWORD_KG, ActionResolutionSystem.swing_speed(weak, Vector3.ZERO, Vector3.FORWARD)
	)
	var strong_e: float = ActionResolutionSystem.impact_energy(
		HUMAN_KG,
		SWORD_KG,
		ActionResolutionSystem.swing_speed(strong, Vector3.ZERO, Vector3.FORWARD)
	)
	assert_gt(strong_e, weak_e, "strength increases delivered energy")


## Weapon choice must matter. Under the old model the weapon contributed 13% and strength 87%,
## so a warhammer felt like a dagger.
func test_heavier_weapon_hits_meaningfully_harder() -> void:
	var body: BodyComponent = _human_body()
	var speed: float = ActionResolutionSystem.swing_speed(body, Vector3.ZERO, Vector3.FORWARD)
	var dagger: float = ActionResolutionSystem.impact_energy(HUMAN_KG, 0.6, speed)
	var hammer: float = ActionResolutionSystem.impact_energy(HUMAN_KG, 8.0, speed)
	assert_gt(hammer / dagger, 1.5, "an 8 kg hammer clearly outclasses a 0.6 kg dagger")


func test_rat_is_one_shot_but_human_is_not() -> void:
	var rat_threshold: float = ActionResolutionSystem.gib_threshold(RAT_KG, 1.0)
	var human_threshold: float = ActionResolutionSystem.gib_threshold(HUMAN_KG, 1.0)
	assert_almost_eq(rat_threshold, 65.0, 3.0, "rat gib threshold is ~65 J")
	assert_almost_eq(human_threshold, 2040.0, 40.0, "human gib threshold is ~2040 J")
	assert_gt(106.0, rat_threshold, "a 106 J swing destroys a rat outright")
	assert_lt(106.0, human_threshold, "the same swing does NOT dismember a human")


## The old threshold was mass * density * K, i.e. volume * density squared. A 200 L water barrel
## came out 1.6x tougher than a plate-armoured knight.
func test_toughness_scales_with_cross_section_not_sheer_mass() -> void:
	var light: float = ActionResolutionSystem.gib_threshold(1.0, 1.0)
	var heavy: float = ActionResolutionSystem.gib_threshold(8.0, 1.0)
	# 8x the mass is only 4x the cross-section (8^(2/3) == 4).
	assert_almost_eq(heavy / light, 4.0, 0.05, "threshold scales as mass^(2/3)")


func test_water_barrel_is_not_tougher_than_a_knight() -> void:
	var barrel: float = ActionResolutionSystem.gib_threshold(200.0, 0.2)
	var knight: float = ActionResolutionSystem.gib_threshold(95.0, 2.5)
	assert_lt(barrel, knight, "an armoured knight is tougher than a barrel of water")


func test_armour_absorbs_more_of_a_weak_blow_than_a_strong_one() -> void:
	var weak: float = ActionResolutionSystem.absorbed_fraction(300.0, 50.0)
	var strong: float = ActionResolutionSystem.absorbed_fraction(300.0, 5000.0)
	assert_gt(weak, strong, "armour is proportionally less effective against heavy blows")
	assert_lte(weak, 0.95, "armour never absorbs everything")


func test_unarmoured_target_absorbs_nothing() -> void:
	assert_eq(ActionResolutionSystem.absorbed_fraction(0.0, 100.0), 0.0, "no armour, no absorb")


## Health must actually be reachable. The old model was a boolean kill test with no bridge to
## BodyComponent.health at all.
func test_three_hits_kill_an_unarmoured_human() -> void:
	var body: BodyComponent = _human_body()
	var speed: float = ActionResolutionSystem.swing_speed(body, Vector3.ZERO, Vector3.FORWARD)
	var energy: float = ActionResolutionSystem.impact_energy(HUMAN_KG, SWORD_KG, speed)
	var damage: float = energy / WorldConstants.J_PER_HP
	assert_almost_eq(damage, 35.4, 1.0, "one hit is ~35 hp")
	assert_lt(body.max_health / damage, 4.0, "three hits suffice")
	assert_gt(body.max_health / damage, 2.0, "but it is not a one-shot")


func test_falling_below_the_safe_speed_is_harmless() -> void:
	var system := ActionResolutionSystem.new()
	var handle: int = ECSManager.allocate_entity()
	var row: int = EH.index_of(handle)
	ECSManager.bodies[row] = _human_body()
	ECSManager.add_component_bit(row, ComponentMask.BODY)
	assert_eq(system.resolve_fall(row, 3.0), 0.0, "a short drop does no damage")
	ECSManager.destroy_entity(handle)


func test_muscle_memory_grows_and_respects_its_cap() -> void:
	var body: BodyComponent = _human_body()
	for _i in 2000:
		body.train_skill(&"Blade_Familiarity", 1.0)
	var cap: float = 60.0 + 0.4 * body.strength
	assert_gt(body.skill(&"Blade_Familiarity"), 0.0, "practice raises the skill")
	assert_lte(body.skill(&"Blade_Familiarity"), cap, "the strength-derived soft cap holds")
