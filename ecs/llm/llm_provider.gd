## What the reasoner is allowed to ask of a thinking service (ADR-5).
##
## ADR-5 WAS AMENDED: the LLM is an OPTIONAL LAYER, not a required dependency. The game must play
## start to finish with no endpoint configured. That is not a degraded mode bolted on afterwards
## — it is the DEFAULT provider, so it runs on every commit in CI and cannot rot.
##
## The reasoning for the amendment is worth keeping next to the code it shaped: ADR-5's own
## Validation Gate and Fallback Matrix already required correct behaviour when every call fails.
## A system that must survive total LLM failure is, by construction, a system with a complete
## heuristic path. The original decision required building that path while forbidding shipping it.
##
## Asynchronous by contract. `request` returns immediately and calls `on_done` later — even the
## heuristic provider, so that swapping in a real endpoint cannot change the shape of any caller.
class_name LLMProvider
extends RefCounted

## Called with the parsed response Dictionary, or an empty Dictionary on any failure. Providers
## never throw and never return null: a caller that has to distinguish four failure shapes will
## get one of them wrong.
func request(_prompt: String, _on_done: Callable) -> void:
	push_error("LLMProvider.request is abstract")


## Human-readable, for the debug overlay. Which brain is driving is not something a player or a
## bug report should have to infer.
func describe() -> String:
	return "abstract"


## True when this provider talks to something outside the process. Used to decide whether a
## per-session request budget applies at all.
func is_remote() -> bool:
	return false
