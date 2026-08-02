## ADR-7 entity lifecycle: generational handles and atomic destroy.
##
## Note these run against the ECSManager autoload, which already reserved index 0 for the
## player at boot, so allocations here start at index 1.
extends GutTest


func test_player_occupies_index_zero() -> void:
	var player: int = ECSManager.player_handle()
	assert_eq(EH.index_of(player), 0, "player is index 0 (ADR-14)")
	assert_true(ECSManager.is_alive(player), "player is alive at boot")
	assert_true(ECSManager.is_player(player), "is_player recognises the player slot")


func test_allocate_produces_distinct_live_handles() -> void:
	var a: int = ECSManager.allocate_entity()
	var b: int = ECSManager.allocate_entity()
	assert_ne(a, b, "handles are distinct")
	assert_true(ECSManager.is_alive(a), "a is alive")
	assert_true(ECSManager.is_alive(b), "b is alive")
	ECSManager.destroy_entity(a)
	ECSManager.destroy_entity(b)


func test_destroyed_handle_is_not_alive() -> void:
	var handle: int = ECSManager.allocate_entity()
	assert_true(ECSManager.destroy_entity(handle), "destroy succeeds once")
	assert_false(ECSManager.is_alive(handle), "handle is dead after destroy")


func test_destroy_is_idempotent_and_rejects_stale() -> void:
	var handle: int = ECSManager.allocate_entity()
	assert_true(ECSManager.destroy_entity(handle), "first destroy succeeds")
	assert_false(ECSManager.destroy_entity(handle), "second destroy is rejected, not fatal")


func test_reused_index_bumps_generation_and_invalidates_stale_handle() -> void:
	var first: int = ECSManager.allocate_entity()
	var index: int = EH.index_of(first)
	var first_gen: int = EH.gen_of(first)
	ECSManager.destroy_entity(first)

	# The freed index is next in the free list, so this reuses it.
	var second: int = ECSManager.allocate_entity()
	assert_eq(EH.index_of(second), index, "index was reused")
	assert_eq(EH.gen_of(second), first_gen + 1, "generation bumped on reuse")
	assert_false(ECSManager.is_alive(first), "the STALE handle must not resolve")
	assert_true(ECSManager.is_alive(second), "the fresh handle resolves")
	ECSManager.destroy_entity(second)


func test_destroy_clears_every_registered_registry() -> void:
	# This is the ADR-7 atomicity guarantee: one destroy, every registry.
	var reg_a: Dictionary = {}
	var reg_b: Dictionary = {}
	ECSManager.register_registry(reg_a)
	ECSManager.register_registry(reg_b)

	var handle: int = ECSManager.allocate_entity()
	var index: int = EH.index_of(handle)
	reg_a[index] = "position"
	reg_b[index] = "needs"

	ECSManager.destroy_entity(handle)
	assert_false(reg_a.has(index), "registry A was cleared")
	assert_false(reg_b.has(index), "registry B was cleared")


func test_stale_handle_rejection_is_counted() -> void:
	var before: int = ECSManager.stale_handle_rejections
	ECSManager.destroy_entity(EH.make(999999, 1))
	assert_gt(
		ECSManager.stale_handle_rejections, before, "stale dereference increments the counter"
	)


func test_alive_count_tracks_allocation() -> void:
	var before: int = ECSManager.alive_count
	var handle: int = ECSManager.allocate_entity()
	assert_eq(ECSManager.alive_count, before + 1, "alive_count rises on allocate")
	ECSManager.destroy_entity(handle)
	assert_eq(ECSManager.alive_count, before, "alive_count falls on destroy")
