## ADR-19 EntityHandle contract.
##
## These tests exist because the ORIGINAL spec used a RefCounted handle as a Dictionary key,
## which silently does not work in GDScript. `test_handle_is_dictionary_safe` is the
## regression guard: if someone reintroduces an object handle, it fails immediately.
extends GutTest


func test_pack_unpack_roundtrip() -> void:
	var handle: int = EH.make(7, 3)
	assert_eq(EH.index_of(handle), 7, "index survives packing")
	assert_eq(EH.gen_of(handle), 3, "generation survives packing")


func test_handle_is_dictionary_safe() -> void:
	# The whole point of ADR-19: two independently constructed handles with the same value
	# must be the SAME Dictionary key.
	var registry: Dictionary = {}
	registry[EH.make(5, 1)] = "component"
	assert_true(registry.has(EH.make(5, 1)), "equal-valued handles hit the same key")
	registry[EH.make(5, 1)] = "overwritten"
	assert_eq(registry.size(), 1, "must overwrite, never create a duplicate key")
	assert_eq(registry[EH.make(5, 1)], "overwritten", "second write wins")


func test_invalid_is_zero_and_detectable() -> void:
	assert_eq(EH.INVALID, 0, "INVALID is 0, not -1 (negative >> is a parse error)")
	assert_false(EH.is_valid(EH.INVALID), "the invalid handle is not valid")
	assert_true(EH.is_valid(EH.make(0, 1)), "index 0 generation 1 IS valid")


func test_invalid_comparison_actually_works() -> void:
	# The old `EntityHandle.invalid()` allocated a new object per call, so this comparison
	# was always false and every "has a target?" check was broken.
	var target: int = EH.INVALID
	assert_true(target == EH.INVALID, "comparison against INVALID must succeed")


func test_index_zero_generation_one_is_the_player_slot() -> void:
	var player: int = EH.make(WorldConstants.PLAYER_INDEX, 1)
	assert_eq(EH.index_of(player), 0, "player is index 0 (ADR-14)")
	assert_true(EH.is_valid(player), "player handle is valid")


func test_high_index_and_generation_do_not_collide() -> void:
	var handle: int = EH.make(0xFFFFFFFF, 12345)
	assert_eq(EH.index_of(handle), 0xFFFFFFFF, "max index round-trips")
	assert_eq(EH.gen_of(handle), 12345, "generation is unaffected by a full-width index")


func test_save_form_survives_json() -> void:
	# ADR-21: a bare packed handle loses precision through JSON because every number parses
	# as a double. The {index, generation} form does not.
	var handle: int = EH.make(123456, 7)
	var encoded: String = JSON.stringify(EH.to_dict(handle))
	var decoded: Variant = JSON.parse_string(encoded)
	assert_eq(EH.from_dict(decoded), handle, "handle round-trips through JSON as a dict")
