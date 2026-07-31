## In-game calendar. The ONLY time source for schedules, logs, climate, memory decay, and save
## timestamps (invariants section 2).
##
## MUST `extends Node` to be autoloadable. Advanced by GameLoopManager's Macro tick, one hour at
## a time. Never reads wall-clock time (ADR-20).
extends Node

const HOURS_PER_DAY: int = 24
const DAYS_PER_SEASON: int = 90
const SEASONS_PER_YEAR: int = 4
const DAYS_PER_YEAR: int = DAYS_PER_SEASON * SEASONS_PER_YEAR

## Day 0 starts at 06:00 (world_bootstrapping). Day is 0-based to match "Day 0" everywhere.
var hour: int = 6
var day: int = 0
var season: int = 0
var year: int = 0

## Monotonic hour counter. Memory decay and any age calculation use THIS, never a subtraction of
## calendar fields.
var elapsed_hours: int = 0


func advance_hour() -> void:
	hour += 1
	elapsed_hours += 1
	if hour >= HOURS_PER_DAY:
		hour = 0
		_advance_day()
	ECSEvents.clock_advanced.emit(hour, day, season, year)


func _advance_day() -> void:
	day += 1
	var day_of_year: int = day % DAYS_PER_YEAR
	season = (day_of_year / DAYS_PER_SEASON) % SEASONS_PER_YEAR
	year = day / DAYS_PER_YEAR


## Total elapsed in-game hours. The age basis for MemoryEvent weighting.
func total_hours() -> int:
	return elapsed_hours


## Advances a whole year without running 8,760 hourly ticks (ADR-9/ADR-11). The Interregnum
## uses 12 coarse monthly passes on ledgers; this only moves the calendar.
func advance_interregnum_year() -> void:
	elapsed_hours += DAYS_PER_YEAR * HOURS_PER_DAY
	day += DAYS_PER_YEAR
	year += 1
	season = 0
	hour = 6
	ECSEvents.clock_advanced.emit(hour, day, season, year)


func is_daylight() -> bool:
	return hour >= 6 and hour < 18


func to_display_string() -> String:
	var names: Array[String] = ["Spring", "Summer", "Autumn", "Winter"]
	return "%s %d %02d:00" % [names[season], (day % DAYS_PER_SEASON) + 1, hour]


func save_to_dict() -> Dictionary:
	return {
		"hour": hour,
		"day": day,
		"season": season,
		"year": year,
		"elapsed_hours": elapsed_hours,
	}


func load_from_dict(data: Dictionary) -> void:
	hour = int(data.get("hour", 6))
	day = int(data.get("day", 0))
	season = int(data.get("season", 0))
	year = int(data.get("year", 0))
	elapsed_hours = int(data.get("elapsed_hours", 0))
