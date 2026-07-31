## Maps hour-of-day to a behavioural block. Reads GameClock (ADR-9).
class_name ScheduleComponent
extends RefCounted

enum Block { SLEEP, WORK, LEISURE }

## Canonical ranges (entity_behavior section 6): Sleep 22-06, Work 06-18, Leisure 18-22.
var sleep_start: int = 22
var work_start: int = 6
var leisure_start: int = 18


func block_for_hour(hour: int) -> Block:
	var h: int = wrapi(hour, 0, 24)
	if h >= work_start and h < leisure_start:
		return Block.WORK
	if h >= leisure_start and h < sleep_start:
		return Block.LEISURE
	return Block.SLEEP


func block_name(block: Block) -> StringName:
	match block:
		Block.SLEEP:
			return &"Sleep"
		Block.WORK:
			return &"Work"
		_:
			return &"Leisure"
