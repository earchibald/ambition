## One thought at a time, and the prompt is built at the last possible moment (Sprint 3 Step 1).
##
## STORES IDS, NEVER PROMPTS. This is the roadmap's explicit requirement and the reason is worth
## restating: a prompt built at enqueue time describes a world that has since moved on. The
## leader then reasons about a siege that ended or a rival that no longer exists, confidently and
## in detail. Stale context is worse than thin context.
##
## ONE IN FLIGHT. Not a throughput choice — a rate-limit and cost choice. Twenty faction leaders
## thinking at once is twenty simultaneous paid calls and a provider 429 that arrives as twenty
## simultaneous failures.
##
## NEVER BLOCKS. `pump` returns immediately whether or not anything is in flight, so the 60 Hz
## loop is untouched by a provider taking two seconds to answer.
class_name ReasoningQueue
extends RefCounted

## Refuse to grow past this. A queue that accepts every request forever is a memory leak whose
## symptom is a leader acting on an hour-old decision.
##
## THIS IS ALSO ADR-12's CAP on simultaneous Tier-3 reasoners, enforced before enqueue as the
## scaffolding (§7) specifies and Sprint 3 shipped without. Every pending entry is a distinct
## faction (`submit` de-duplicates), so the pending bound IS the faction cap — one constant,
## because two bounds on the same quantity is how they drift. The 25th faction is refused and
## counted, never silently queued. Schism consults this same constant before creating a faction
## at all, so the two enforcement points cannot disagree.
const MAX_PENDING: int = 24

## Priority classes (declared gap G-5). The queue was strictly FIFO, so a faction under attack
## waited behind routine weekly thinking. Lower value pops first; FIFO within a class, by
## submission sequence, so no starvation reordering happens inside a class.
const PRIORITY_CRISIS: int = 0
const PRIORITY_DIPLOMATIC: int = 1
const PRIORITY_ROUTINE: int = 2

## Ceiling on cached responses. The cache was unbounded until 2026-08-01, and both output audits
## found it independently: a prompt changes whenever the world does, so over a long run the
## number of distinct prompts is unbounded and the "cost control" was a slow memory leak.
## Oldest-first eviction is right here — an old prompt describes a world that has moved on, so it
## is both the least likely to hit again and the least harmful to lose.
const MAX_CACHED: int = 128

## Per-session ceiling on REMOTE calls. Local providers are free and are not counted, so running
## without an endpoint has no budget at all.
const DEFAULT_SESSION_BUDGET: int = 200

var provider: LLMProvider
var session_budget: int = DEFAULT_SESSION_BUDGET

var enqueued: int = 0
var dispatched: int = 0
var completed: int = 0
var rejected_full: int = 0
var duplicates_skipped: int = 0
var priority_upgrades: int = 0
var budget_exhausted: bool = false
var cache_hits: int = 0

## Each entry: {handle, priority, seq}. Popped by (priority, seq), so a crisis submitted after a
## week of routine thinking still fires first, and two crises fire in the order they happened.
var _pending: Array[Dictionary] = []
var _queued: Dictionary = {}
var _seq: int = 0
var _in_flight: int = EH.INVALID
## prompt hash -> response, for the duration of a run (ADR-5 cost control).
var _cache: Dictionary = {}
## Insertion order, so eviction is oldest-first without reading wall-clock time (ADR-20).
var _cache_order: Array[String] = []


func _init(chosen: LLMProvider = null) -> void:
	provider = HeuristicProvider.new() if chosen == null else chosen


## Registers a leader as wanting to think. Idempotent: asking twice while still queued is a
## no-op, because two decisions for one faction in one hour is one wasted call — EXCEPT that a
## re-submit at higher urgency upgrades the queued request in place. A faction that queued its
## weekly review and then got attacked must jump the line, not wait behind it.
func submit(faction_handle: int, priority: int = PRIORITY_ROUTINE) -> bool:
	if _queued.has(faction_handle) or _in_flight == faction_handle:
		duplicates_skipped += 1
		for entry in _pending:
			if int(entry["handle"]) == faction_handle and priority < int(entry["priority"]):
				entry["priority"] = priority
				priority_upgrades += 1
				break
		return false
	if _pending.size() >= MAX_PENDING:
		rejected_full += 1
		return false
	_pending.append({"handle": faction_handle, "priority": priority, "seq": _seq})
	_seq += 1
	_queued[faction_handle] = true
	enqueued += 1
	return true


func is_busy() -> bool:
	return EH.is_valid(_in_flight)


func pending_count() -> int:
	return _pending.size()


## Fires the next request if the line is free. Called once per Macro tick.
func pump(generator: DAGGenerator, on_answer: Callable) -> void:
	if is_busy() or _pending.is_empty():
		return
	var handle: int = _pop_most_urgent()
	_queued.erase(handle)

	# THE VALIDATION GATE, FIRST HALF: the leader may have died while queued. Spending a paid
	# call on a corpse is the cheapest possible thing to avoid.
	if not ECSManager.is_alive(handle):
		return
	var row: int = ECSManager.resolve(handle)
	var core: FactionCoreComponent = ECSManager.faction_cores.get(row)
	if core == null:
		return

	if provider.is_remote() and session_budget <= 0:
		budget_exhausted = true
		return

	# BUILT HERE, at the moment of dispatch. Not at submit time.
	var prompt: String = PromptBuilder.build(core.faction_id, generator)
	if prompt == "":
		return

	var key: String = str(prompt.hash())
	if _cache.has(key):
		cache_hits += 1
		completed += 1
		on_answer.call(handle, _cache[key])
		return

	_in_flight = handle
	dispatched += 1
	if provider.is_remote():
		session_budget -= 1
	provider.request(prompt, func(response: Dictionary) -> void:
		_in_flight = EH.INVALID
		completed += 1
		if not response.is_empty():
			_remember(key, response)
		on_answer.call(handle, response)
	)


## Lowest (priority, seq) wins. A linear scan, because the queue is capped at 24 entries and a
## heap would be more code guarding against a size that cannot occur.
func _pop_most_urgent() -> int:
	var best: int = 0
	for i in range(1, _pending.size()):
		var entry: Dictionary = _pending[i]
		var champion: Dictionary = _pending[best]
		if (
			int(entry["priority"]) < int(champion["priority"])
			or (
				int(entry["priority"]) == int(champion["priority"])
				and int(entry["seq"]) < int(champion["seq"])
			)
		):
			best = i
	var chosen: Dictionary = _pending[best]
	_pending.remove_at(best)
	return int(chosen["handle"])


## Bounded, oldest-first. A dictionary that only ever grows is a leak whatever it is called.
func _remember(key: String, response: Dictionary) -> void:
	if not _cache.has(key):
		_cache_order.append(key)
	_cache[key] = response
	while _cache_order.size() > MAX_CACHED:
		_cache.erase(_cache_order.pop_front())


func counters() -> Dictionary:
	return {
		"reason_provider": provider.describe(),
		"reason_enqueued": enqueued,
		"reason_dispatched": dispatched,
		"reason_completed": completed,
		"reason_pending": _pending.size(),
		"reason_cache_hits": cache_hits,
		"reason_duplicates": duplicates_skipped,
		"reason_rejected_full": rejected_full,
		"reason_priority_upgrades": priority_upgrades,
		"reason_budget_left": session_budget,
		"reason_cached": _cache.size(),
		"reason_budget_exhausted": budget_exhausted,
	}
