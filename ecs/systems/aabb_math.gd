## Pure AABB and ray math. No engine physics.
class_name AABBMath
extends RefCounted


## Slab-method ray/AABB intersection. Returns the entry distance along `dir`, or -1.0 for a
## miss. `dir` must be normalized.
static func ray_aabb(
	origin: Vector3, dir: Vector3, centre: Vector3, half_extents: Vector3, max_t: float
) -> float:
	var t_min: float = 0.0
	var t_max: float = max_t
	var lo: Vector3 = centre - half_extents
	var hi: Vector3 = centre + half_extents

	for axis in 3:
		var d: float = dir[axis]
		var o: float = origin[axis]
		if absf(d) < 0.000001:
			# Parallel to this slab: miss unless already inside it.
			if o < lo[axis] or o > hi[axis]:
				return -1.0
			continue
		var inv: float = 1.0 / d
		var t1: float = (lo[axis] - o) * inv
		var t2: float = (hi[axis] - o) * inv
		if t1 > t2:
			var swap: float = t1
			t1 = t2
			t2 = swap
		t_min = maxf(t_min, t1)
		t_max = minf(t_max, t2)
		if t_min > t_max:
			return -1.0
	return t_min


static func overlaps(
	centre_a: Vector3, half_a: Vector3, centre_b: Vector3, half_b: Vector3
) -> bool:
	return (
		absf(centre_a.x - centre_b.x) <= half_a.x + half_b.x
		and absf(centre_a.y - centre_b.y) <= half_a.y + half_b.y
		and absf(centre_a.z - centre_b.z) <= half_a.z + half_b.z
	)


## Penetration depth on the axis of least overlap, used for the final depenetration pass.
static func min_translation(
	centre_a: Vector3, half_a: Vector3, centre_b: Vector3, half_b: Vector3
) -> Vector3:
	var delta: Vector3 = centre_a - centre_b
	var overlap := Vector3(
		half_a.x + half_b.x - absf(delta.x),
		half_a.y + half_b.y - absf(delta.y),
		half_a.z + half_b.z - absf(delta.z)
	)
	if overlap.x <= 0.0 or overlap.y <= 0.0 or overlap.z <= 0.0:
		return Vector3.ZERO
	if overlap.x <= overlap.y and overlap.x <= overlap.z:
		return Vector3(signf(delta.x) * overlap.x, 0.0, 0.0)
	if overlap.z <= overlap.y:
		return Vector3(0.0, 0.0, signf(delta.z) * overlap.z)
	return Vector3(0.0, signf(delta.y) * overlap.y, 0.0)
