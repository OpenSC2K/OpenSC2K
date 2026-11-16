class_name RemoteHttpRequest
extends RefCounted
## One HTTP request of the remote API, and its answer. A handler answers
## once with respond(), respond_json() or respond_error(), at once or in a
## later frame.

const STATUS_TEXTS := {
	200: "OK", 202: "Accepted", 204: "No Content", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
	405: "Method Not Allowed", 411: "Length Required", 413: "Content Too Large", 431: "Request Header Fields Too Large",
	500: "Internal Server Error", 503: "Service Unavailable",
}
const JSON_TYPE := "application/json"
const TEXT_TYPE := "text/plain; charset=utf-8"

var method := ""
# the path without the query, such as /eval
var path := ""
# the query values, decoded
var query: Dictionary[String, String] = {}
# header name in lower case -> value
var headers: Dictionary[String, String] = {}
var body := PackedByteArray()
var answered := false
# (bytes: PackedByteArray) -> void. The connection sends the bytes
var sink: Callable


## The request of a head text, or null when the text is not an HTTP request head.
static func parse(head: String) -> RemoteHttpRequest:
	var lines := head.split("\r\n")
	var words := lines[0].split(" ")

	if words.size() != 3 or not words[2].begins_with("HTTP/1."):
		return null

	var request := RemoteHttpRequest.new()
	request.method = words[0].to_upper()
	request.path = words[1].get_slice("?", 0).uri_decode()

	if words[1].contains("?"):
		for pair in words[1].get_slice("?", 1).split("&", false):
			var value := pair.get_slice("=", 1).replace("+", " ").uri_decode() if pair.contains("=") else ""
			request.query[pair.get_slice("=", 0).uri_decode()] = value

	for index in range(1, lines.size()):
		var colon := lines[index].find(":")

		if colon > 0:
			request.headers[lines[index].substr(0, colon).strip_edges().to_lower()] = lines[index].substr(colon + 1).strip_edges()

	return request


func header(name: String, fallback := "") -> String:
	return headers.get(name, fallback)


func body_text() -> String:
	return body.get_string_from_utf8()


## The body as JSON data, or null when it is not JSON.
func body_json() -> Variant:
	var json := JSON.new()

	return json.data if json.parse(body_text()) == OK else null


## Sends the answer. A second answer is ignored.
func respond(status: int, content_type: String, content: PackedByteArray, extra_headers: Dictionary = {}) -> void:
	if answered:
		return

	answered = true
	var lines := PackedStringArray(["HTTP/1.1 %d %s" % [status, STATUS_TEXTS.get(status, "Status")]])

	if status != 204:
		lines.append("Content-Type: %s" % content_type)

	lines.append("Content-Length: %d" % content.size())
	lines.append("Cache-Control: no-store")

	for name: String in extra_headers:
		lines.append("%s: %s" % [name, extra_headers[name]])

	var bytes := ("\r\n".join(lines) + "\r\n\r\n").to_utf8_buffer()
	bytes.append_array(content)

	if sink.is_valid():
		sink.call(bytes)


func respond_text(status: int, text: String, content_type := TEXT_TYPE) -> void:
	respond(status, content_type, text.to_utf8_buffer())


## Sends JSON text that the caller made.
func respond_json_text(status: int, json: String) -> void:
	respond(status, JSON_TYPE, json.to_utf8_buffer())


func respond_json(status: int, data: Variant) -> void:
	respond_json_text(status, JSON.stringify(data))


func respond_error(status: int, message: String) -> void:
	respond_json(status, {"ok": false, "error": message})
