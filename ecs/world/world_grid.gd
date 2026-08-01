## The map of the world: chunk_id -> ChunkData, with lazy generation.
##
## Also the TILE SAMPLER the collision and pick systems resolve against. Sprint 1 handed those
## systems a single ChunkData, which was correct while the world was one hand-authored room and
## becomes a wall the moment there are neighbours: `world_to_tile` on the wrong chunk returns an
## out-of-range tile, `in_bounds` rejects it, and the mover is stopped dead on the seam. Sampling
## through the grid is what makes the chunk boundary invisible to the player.
##
## `ChunkData` implements the same three world-space methods, so tests and the Sprint 1 arena can
## still pass a bare chunk wherever a sampler is expected.
class_name WorldGrid
extends TileSampler

## The village occupies this many chunks either side of the origin on floor 0, generated
## SYNCHRONOUSLY at boot. The roadmap is explicit about why: Pre-Warm runs AI pathfinding across
## the whole village, and pathing into a chunk that does not exist yet is a crash, not a stall.
const VILLAGE_RADIUS_CHUNKS: int = 1

const VILLAGE_FLOOR: int = 0

var chunks: Dictionary = {}
## Which floor the sampler answers for. Floors are discrete planes (ADR-3), so a world Y does
## NOT identify a floor — the active floor is world state and is carried here.
var current_floor: int = VILLAGE_FLOOR

var master_seed: int = 0
var chunks_generated: int = 0
var lazy_generations: int = 0


func _init(seed_value: int = 0) -> void:
	master_seed = seed_value


## Every chunk the village occupies. Fixed, small, and generated up front.
func village_chunk_ids() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in range(-VILLAGE_RADIUS_CHUNKS, VILLAGE_RADIUS_CHUNKS + 1):
		for x in range(-VILLAGE_RADIUS_CHUNKS, VILLAGE_RADIUS_CHUNKS + 1):
			out.append(Vector3i(x, y, VILLAGE_FLOOR))
	return out


## Roadmap Step 2: the village exists in memory instantly; dungeon floors do not.
func generate_village() -> void:
	for chunk_id in village_chunk_ids():
		var chunk: ChunkData = _generate(chunk_id)
		# SIMULATED, not ACTIVE: ready for Pre-Warm to run jobs across it, without paying for
		# collision and fluid physics in chunks the player cannot see yet.
		chunk.state = ECSEnums.LoD.SIMULATED
	# One stairwell down, in the middle of the village.
	FloorGenerator.place_stairs(chunk_at(Vector3i.ZERO), Vector2i(32, 32))


## THE lookup. Generates on demand, so a dungeon floor costs nothing until something reaches it.
func chunk_at(chunk_id: Vector3i) -> ChunkData:
	var existing: ChunkData = chunks.get(chunk_id)
	if existing != null:
		return existing
	lazy_generations += 1
	return _generate(chunk_id)


func has_chunk(chunk_id: Vector3i) -> bool:
	return chunks.has(chunk_id)


## Which chunk owns a world position. Floors are discrete (ADR-3), so Y does NOT select the
## chunk — the floor index does, and it is carried separately.
func chunk_id_for(world: Vector3, floor_index: int) -> Vector3i:
	var size: float = WorldConstants.CHUNK_SIZE_M
	return Vector3i(
		int(floor(world.x / size)), int(floor(world.z / size)), floor_index
	)


# --- Tile sampler contract. ChunkData implements these three identically. -----------------

func solid_at_world(world: Vector3) -> bool:
	return chunk_at(chunk_id_for(world, current_floor)).solid_at_world(world)


func height_at_world(world: Vector3) -> float:
	return chunk_at(chunk_id_for(world, current_floor)).height_at_world(world)


## Always true: the grid is unbounded, because it generates whatever is asked for. This is the
## method that makes seams disappear — the single-chunk version returns false off its own edge
## and the mover is blocked there.
func contains_world(_world: Vector3) -> bool:
	return true


# --- Spatial anchors ----------------------------------------------------------------------

## Roadmap Step 2 GESTALT FIX: give every faction a real home chunk.
##
## Anchors are assigned HERE and nowhere else. The DAG deliberately leaves them unset, because
## two systems writing the same field means the later writer silently wins and the bug surfaces
## as "everyone spawned in the same place".
func assign_anchors(faction_nodes: Array[DAGNode]) -> void:
	var taken: Dictionary = {}
	for node in faction_nodes:
		if node.has_anchor():
			continue
		node.anchor_chunk_id = _pick_anchor(node, taken)
		taken[node.anchor_chunk_id] = node.node_id


## One faction per chunk. Two factions sharing an anchor would spawn their populations on top of
## each other and read as a collision bug rather than a generation one.
func _pick_anchor(node: DAGNode, taken: Dictionary) -> Vector3i:
	if node.tags.has(&"SurfaceVillage"):
		return Vector3i(0, 0, VILLAGE_FLOOR)
	var rng: RandomNumberGenerator = FloorGenerator.chunk_rng(
		Vector3i(node.node_id, node.home_floor, 0), master_seed
	)
	# Bounded search, then a deterministic fallback. An unbounded "keep rolling until free" loop
	# never terminates once the floor fills up.
	for _attempt in 32:
		var candidate := Vector3i(
			rng.randi_range(-4, 4), rng.randi_range(-4, 4), node.home_floor
		)
		if not taken.has(candidate):
			return candidate
	return Vector3i(node.node_id, 0, node.home_floor)


func _generate(chunk_id: Vector3i) -> ChunkData:
	var chunk: ChunkData = FloorGenerator.generate(chunk_id, master_seed)
	chunks[chunk_id] = chunk
	chunks_generated += 1
	return chunk


func counters() -> Dictionary:
	return {
		"chunks_generated": chunks_generated,
		"chunks_resident": chunks.size(),
		"lazy_generations": lazy_generations,
	}
