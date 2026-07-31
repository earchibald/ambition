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


## Top-N by current weight, for the LLM salience filter and the gossip picker.
func most_salient(count: int) -> Array[MemoryEvent]:
	var now: int = GameClock.total_hours()
	var sorted: Array[MemoryEvent] = events.duplicate()
	sorted.sort_custom(func(a, b): return a.weight_at(now) > b.weight_at(now))
	return sorted.slice(0, count)
