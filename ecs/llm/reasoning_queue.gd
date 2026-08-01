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
const MAX_PENDING: int = 32

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
var budget_exhausted: bool = false
var cache_hits: int = 0

var _pending: Array[int] = []
var _queued: Dictionary = {}
var _in_flight: int = EH.INVALID
## prompt hash -> response, for the duration of a run (ADR-5 cost control).
var _cache: Dictionary = {}


func _init(chosen: LLMProvider = null) -> void:
	provider = HeuristicProvider.new() if chosen == null else chosen


## Registers a leader as wanting to think. Idempotent: asking twice while still queued is a
## no-op, because two decisions for one faction in one hour is one wasted call.
func submit(faction_handle: int) -> bool:
	if _queued.has(faction_handle) or _in_flight == faction_handle:
		duplicates_skipped += 1
		return false
	if _pending.size() >= MAX_PENDING:
		rejected_full += 1
		return false
	_pending.append(faction_handle)
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
	var handle: int = _pending.pop_front()
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
			_cache[key] = response
		on_answer.call(handle, response)
	)


func counters() -> Dictionary:
	return {
		"reason_provider": provider.describe(),
		"reason_enqueued": enqueued,
		"reason_dispatched": dispatched,
		"reason_completed": completed,
		"reason_pending": _pending.size(),
		"reason_cache_hits": cache_hits,
		"reason_duplicates": duplicates_skipped,
		"reason_budget_left": session_budget,
	}
