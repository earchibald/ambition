## What an entity remembers.
##
## Bounded on purpose: the gossip loop unions memory lists between NPCs, so without a cap and
## an event_id to dedup on, 200 NPCs x 30 events converges to 1.2M records.
class_name MemoryComponent
extends RefCounted

const MEMORY_CAP: int = 32

var events: Array[MemoryEvent] = []


func remember(event: MemoryEvent) -> bool:
	for existing in events:
		if existing.event_id == event.event_id:
			return false
	events.append(event)
	_evict_if_needed()
	return true


## Evicts the lowest-weight NON-CORE event. Core memories are never evicted by overflow.
func _evict_if_needed() -> void:
	if events.size() <= MEMORY_CAP:
		return
	var worst_index: int = -1
	var worst_weight: float = INF
	for i in events.size():
		if events[i].core:
			continue
		var weight: float = events[i].weight_at(GameClock.total_hours())
		if weight < worst_weight:
			worst_weight = weight
			worst_index = i
	if worst_index >= 0:
		events.remove_at(worst_index)


## Top-N by current weight. Read by `PromptBuilder` for the leader's personal memories (G-8).
##
## TOTALLY ORDERED. This compared weight alone with the unstable `sort_custom`, which is the
## exact defect fixed twice already in `PromptBuilder` and `prune_diplomacy`: ties selected
## DIFFERENT memories run to run, breaking ADR-20 reproducibility and silently missing the
## prompt-hash cache. Tie-break ends in `event_id`, which is globally unique.
func most_salient(count: int) -> Array[MemoryEvent]:
	var now: int = GameClock.total_hours()
	var sorted: Array[MemoryEvent] = events.duplicate()
	sorted.sort_custom(
		func(a: MemoryEvent, b: MemoryEvent) -> bool:
			var weight_a: float = a.weight_at(now)
			var weight_b: float = b.weight_at(now)
			if not is_equal_approx(weight_a, weight_b):
				return weight_a > weight_b
			return a.event_id < b.event_id
	)
	return sorted.slice(0, count)
