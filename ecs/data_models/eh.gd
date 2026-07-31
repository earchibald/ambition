## EntityHandle packing (ADR-19).
##
## A handle is a PLAIN 64-BIT INT, never an object:
##     index      = h & 0xFFFFFFFF   (low 32 bits)
##     generation = h >> 32          (high bits)
##
## WHY NOT AN OBJECT: a `RefCounted` handle CANNOT be used as a Dictionary key in GDScript.
## It hashes by object identity, so a value-identical handle misses and the Dictionary
## silently grows a duplicate entry. A script-defined `hash()`/`_eq()` is ignored by
## `Dictionary`. This is verified, and it is why every registry keys on this int.
##
## WHY `INVALID = 0` AND NOT `-1`: GDScript's `>>` rejects negative operands, and a
## constant-folded `-1 >> 32` is a hard parse error. Generations start at 1, so 0 is never
## a live handle and an uninitialised int is detectable.
##
## Saves serialize as `{"index": i, "generation": g}` — never a bare packed int, because
## Godot's JSON parses every number as a double and loses precision above 2^53 (ADR-21).
class_name EH
extends RefCounted

const INVALID: int = 0
const INDEX_MASK: int = 0xFFFFFFFF
const MAX_INDEX: int = 0xFFFFFFFF
const MAX_GENERATION: int = 0x7FFFFFFF


static func make(index: int, generation: int) -> int:
	assert(index >= 0 and index <= MAX_INDEX, "entity index out of range")
	assert(generation >= 1 and generation <= MAX_GENERATION, "generation must be >= 1")
	return (generation << 32) | (index & INDEX_MASK)


static func index_of(handle: int) -> int:
	return handle & INDEX_MASK


static func gen_of(handle: int) -> int:
	return handle >> 32


static func is_valid(handle: int) -> bool:
	return handle > 0


## Save form (ADR-21). Two sub-2^32 ints survive JSON's double coercion; a packed handle
## does not.
static func to_dict(handle: int) -> Dictionary:
	return {"index": index_of(handle), "generation": gen_of(handle)}


static func from_dict(data: Dictionary) -> int:
	return make(int(data["index"]), int(data["generation"]))


## Human-readable form for logs and the debug inspector.
static func to_debug_string(handle: int) -> String:
	if not is_valid(handle):
		return "<invalid>"
	return "e%d:g%d" % [index_of(handle), gen_of(handle)]
