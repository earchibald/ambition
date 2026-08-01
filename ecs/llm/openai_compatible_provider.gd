## Talks to any OpenAI-compatible /chat/completions endpoint (ADR-5).
##
## OPTIONAL. Nothing constructs this unless an endpoint is configured; `HeuristicProvider` is the
## default and the game is complete without ever loading this file.
##
## THE KEY IS NEVER COMMITTED. It comes from an environment variable or a `user://` file, both of
## which are outside the repository, and `.gitignore` covers the config path as a second line of
## defence. The key is never written to a log or a counter — `describe()` reports the endpoint
## and model only.
##
## `HTTPRequest` is a Node, so this owns one and parents it to the tree. That is not a Prime
## Directive violation: the ban is on Godot PHYSICS nodes standing in for simulation state, and
## an HTTP client is I/O, exactly like the renderer. It holds no game state.
class_name OpenAICompatibleProvider
extends LLMProvider

const ENV_ENDPOINT: String = "DELVE_LLM_ENDPOINT"
const ENV_MODEL: String = "DELVE_LLM_MODEL"
const ENV_KEY: String = "DELVE_LLM_API_KEY"
const KEY_FILE: String = "user://llm_secrets.cfg"

const TIMEOUT_S: float = 20.0

var endpoint: String = ""
var model: String = "gpt-4o-mini"

var _api_key: String = ""
var _http: HTTPRequest = null
var _on_done: Callable = Callable()


## Returns null unless an endpoint AND a key are both configured. A half-configured provider that
## fails every call is worse than no provider: it burns the queue and hides the heuristic path.
static func create_if_configured(host: Node) -> OpenAICompatibleProvider:
	var endpoint_value: String = OS.get_environment(ENV_ENDPOINT)
	if endpoint_value == "":
		return null
	var provider := OpenAICompatibleProvider.new()
	provider.endpoint = endpoint_value
	var model_value: String = OS.get_environment(ENV_MODEL)
	if model_value != "":
		provider.model = model_value
	provider._api_key = provider._read_key()
	if provider._api_key == "":
		push_warning("%s is set but no API key was found; using the heuristic reasoner" % ENV_ENDPOINT)
		return null
	provider._attach(host)
	return provider


func describe() -> String:
	# Endpoint and model ONLY. A key that reaches a debug overlay reaches a screenshot.
	return "%s (%s)" % [model, endpoint]


func is_remote() -> bool:
	return true


func request(prompt: String, on_done: Callable) -> void:
	if _http == null:
		on_done.call({})
		return
	_on_done = on_done
	var body: Dictionary = {
		"model": model,
		"response_format": {"type": "json_object"},
		"messages": [{"role": "user", "content": prompt}],
	}
	var headers: PackedStringArray = PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % _api_key,
	])
	var error: int = _http.request(
		"%s/chat/completions" % endpoint.rstrip("/"),
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(body)
	)
	if error != OK:
		# Report failure through the SAME empty-Dictionary channel as every other fault, so the
		# validation gate has exactly one shape to handle.
		_finish({})


func _attach(host: Node) -> void:
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	host.add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _on_request_completed(
	_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if response_code < 200 or response_code >= 300:
		_finish({})
		return
	var envelope: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(envelope) != TYPE_DICTIONARY:
		_finish({})
		return
	var choices: Array = envelope.get("choices", [])
	if choices.is_empty():
		_finish({})
		return
	var content: String = String(choices[0].get("message", {}).get("content", ""))
	var parsed: Variant = JSON.parse_string(content)
	_finish({} if typeof(parsed) != TYPE_DICTIONARY else parsed)


func _finish(response: Dictionary) -> void:
	if _on_done.is_valid():
		var callback: Callable = _on_done
		_on_done = Callable()
		callback.call(response)


## Environment first, then a `user://` file. Both live outside the repository; the config path is
## also in `.gitignore` so a stray copy inside the tree still cannot be committed.
func _read_key() -> String:
	var from_env: String = OS.get_environment(ENV_KEY)
	if from_env != "":
		return from_env
	if not FileAccess.file_exists(KEY_FILE):
		return ""
	var file: FileAccess = FileAccess.open(KEY_FILE, FileAccess.READ)
	return "" if file == null else file.get_as_text().strip_edges()
