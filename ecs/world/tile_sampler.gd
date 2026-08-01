## What collision and picking are allowed to ask about terrain.
##
## Two things implement it: a single `ChunkData` (a sealed room — everything outside its own
## 64x64 reads as solid) and the whole `WorldGrid` (unbounded, generating neighbours on demand).
## Because both satisfy the same contract, Sprint 1's hand-authored arena and Sprint 2's streamed
## world drive exactly the same collision code, and the tests can keep using a bare chunk.
##
## This exists as a real base class rather than duck typing so the signatures are checked at
## parse time. A sampler that silently lacks `height_at_world` would otherwise surface as every
## entity standing at elevation zero.
class_name TileSampler
extends RefCounted


## True if the tile containing `world` blocks movement.
func solid_at_world(_world: Vector3) -> bool:
	push_error("TileSampler.solid_at_world is abstract")
	return true


## Floor elevation in metres at `world`. This is the value the step-up and drop rules compare.
func height_at_world(_world: Vector3) -> float:
	push_error("TileSampler.height_at_world is abstract")
	return 0.0


## Whether this sampler can answer for `world` at all. A lone chunk says no beyond its edge; the
## grid always says yes, which is precisely what makes chunk seams invisible to a mover.
func contains_world(_world: Vector3) -> bool:
	push_error("TileSampler.contains_world is abstract")
	return false
