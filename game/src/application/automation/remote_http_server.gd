class_name RemoteHttpServer
extends RefCounted
## A small HTTP/1.1 server for the remote API. It listens on 127.0.0.1 only
## and runs on the main thread: poll() reads and writes without waiting.
## A request must name this computer in its Host header and must not come
## from a web page: a page that a browser shows sends an Origin header. Each
## request goes to `handler`, which answers at once or in a later frame with
## RemoteHttpRequest.respond().

const ADDRESS := "127.0.0.1"
# a request head or body above these sizes closes the connection
const MAX_HEAD_BYTES := 16 * 1024
const MAX_BODY_BYTES := 8 * 1024 * 1024
# a connection that sends no request for this long closes
const IDLE_MSEC := 60000
const MAX_CONNECTIONS := 16
const LOCAL_HOSTS: PackedStringArray = ["127.0.0.1", "localhost", "[::1]"]
const HEAD_END := "\r\n\r\n"

# (request: RemoteHttpRequest) -> void
var handler: Callable
var _server := TCPServer.new()
var _port := 0
var _connections: Array[Connection] = []


## Starts to listen. Port 0 selects a free port. Returns an empty text, or
## why the server cannot listen.
func start(port: int) -> String:
	stop()
	var error := _server.listen(port, ADDRESS)

	if error != OK:
		return "Cannot listen on port %d: %s." % [port, error_string(error)]

	_port = _server.get_local_port()

	return ""


func stop() -> void:
	for connection in _connections:
		connection.peer.disconnect_from_host()

	_connections.clear()

	if _server.is_listening():
		_server.stop()

	_port = 0


## The port of the server, or 0 when it does not listen.
func port() -> int:
	return _port


func is_listening() -> bool:
	return _port > 0


## Accepts connections, reads requests and writes answers. Call it each frame.
func poll() -> void:
	if not is_listening():
		return

	while _server.is_connection_available():
		var peer := _server.take_connection()

		if _connections.size() >= MAX_CONNECTIONS:
			peer.disconnect_from_host()
		else:
			peer.set_no_delay(true)
			_connections.append(Connection.new(peer))

	var now := Time.get_ticks_msec()

	for connection in _connections.duplicate():
		if not _poll_connection(connection, now):
			connection.peer.disconnect_from_host()
			_connections.erase(connection)


# false when the connection is done
func _poll_connection(connection: Connection, now: int) -> bool:
	var peer := connection.peer
	peer.poll()

	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false

	if not _write(connection):
		return false

	var answered := connection.request != null and connection.request.answered

	# the client asked for one answer on this connection, and it left
	if connection.close_after_write and answered and connection.output.is_empty():
		return false

	var available := peer.get_available_bytes()

	if available > 0:
		var chunk := peer.get_partial_data(available)

		if int(chunk[0]) != OK:
			return false

		connection.input.append_array(chunk[1])
		connection.active_msec = now

	if connection.request == null:
		_read_request(connection)
	elif answered and connection.output.is_empty():
		# the answer left; the next request of this connection can start
		connection.request = null
		connection.active_msec = now
		_read_request(connection)

	return connection.request != null or now - connection.active_msec < IDLE_MSEC


# sends the waiting bytes. False when the connection broke
func _write(connection: Connection) -> bool:
	if connection.output.is_empty():
		return true

	var sent := connection.peer.put_partial_data(connection.output)

	if int(sent[0]) != OK:
		return false

	connection.output = connection.output.slice(int(sent[1]))

	return true


# starts the request in the input when its head and body arrived
func _read_request(connection: Connection) -> void:
	if connection.close_after_write:
		return

	var head_end := _find(connection.input, HEAD_END.to_ascii_buffer())

	if head_end < 0:
		if connection.input.size() > MAX_HEAD_BYTES:
			_refuse(connection, 431, "The request head is too large.")

		return

	var request := RemoteHttpRequest.parse(connection.input.slice(0, head_end).get_string_from_utf8())

	if request == null:
		_refuse(connection, 400, "This is not an HTTP request.")

		return

	var length := request.header("content-length", "0")

	if request.headers.has("transfer-encoding") or not length.is_valid_int() or int(length) < 0:
		_refuse(connection, 411, "Send the body with a Content-Length header.")

		return

	if int(length) > MAX_BODY_BYTES:
		_refuse(connection, 413, "The request body is too large.")

		return

	var body_start := head_end + HEAD_END.length()

	if connection.input.size() < body_start + int(length):
		# curl waits for this line before it sends a large body
		if request.header("expect").to_lower() == "100-continue" and not connection.continued:
			connection.continued = true
			connection.output.append_array("HTTP/1.1 100 Continue\r\n\r\n".to_ascii_buffer())

		return

	request.body = connection.input.slice(body_start, body_start + int(length))
	connection.input = connection.input.slice(body_start + int(length))
	connection.continued = false
	connection.request = request
	request.sink = connection.send
	connection.close_after_write = request.header("connection").to_lower() == "close"
	var refusal := _access_error(request)

	if not refusal.is_empty():
		request.respond_error(403, refusal)
	elif handler.is_valid():
		handler.call(request)
	else:
		request.respond_error(503, "The server has no handler.")


# why the request is refused, or an empty text. A web page of another site
# reaches 127.0.0.1 through the browser of the player; its requests carry an
# Origin header, or a Host name that is not this computer
func _access_error(request: RemoteHttpRequest) -> String:
	var host := request.header("host").to_lower()
	var name := host.get_slice("]", 0) + "]" if host.begins_with("[") else host.get_slice(":", 0)

	if not LOCAL_HOSTS.has(name):
		return "The Host header must name 127.0.0.1 or localhost."

	if request.headers.has("origin"):
		return "Requests from web pages are refused."

	return ""


func _refuse(connection: Connection, status: int, message: String) -> void:
	var request := RemoteHttpRequest.new()
	request.sink = connection.send
	connection.request = request
	connection.close_after_write = true
	connection.input.clear()
	request.respond_error(status, message)


# the index of the first `pattern` in `bytes`, or -1
static func _find(bytes: PackedByteArray, pattern: PackedByteArray) -> int:
	var first := pattern[0]
	var from := 0

	while true:
		var index := bytes.find(first, from)

		if index < 0 or index + pattern.size() > bytes.size():
			return -1

		if bytes.slice(index, index + pattern.size()) == pattern:
			return index

		from = index + 1

	return -1


## One client connection: the bytes that arrived, the bytes to send, and the
## request that waits for its answer.
class Connection extends RefCounted:
	var peer: StreamPeerTCP
	var input := PackedByteArray()
	var output := PackedByteArray()
	var request: RemoteHttpRequest
	var active_msec := Time.get_ticks_msec()
	var close_after_write := false
	# the 100 Continue line of the waiting request was sent
	var continued := false


	func _init(stream: StreamPeerTCP) -> void:
		peer = stream


	func send(bytes: PackedByteArray) -> void:
		output.append_array(bytes)
