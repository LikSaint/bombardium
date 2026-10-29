extends Node
## Autoloaded as `Log`. One log for everything worth knowing after something has gone wrong, in
## one file, so a bug report is "send bombardium.log" and not a hunt through several.
##
##   user://logs/bombardium.log     (on a Steam Deck: ~/.local/share/godot/app_userdata/Bombardium/logs/)
##
## What makes it more use than Godot's own log:
##
##   * Every line is flushed to disk as it is written. Godot's log is buffered, and a native crash
##     (an exported build segfaults where the editor only prints an error — see Arena.get_temp_wall)
##     left it empty; here the last line in the file is the last thing that happened.
##   * It also takes in what the engine reports — print(), push_error(), script errors with their
##     backtraces, shader and driver warnings — so nothing is split between two files.
##   * Sessions follow each other in the one file, each opened with a header (build, OS, GPU, pads)
##     and closed with an "end" line. A session with no end line is the one that was killed, and the
##     next start says so (see _check_previous_session).
##   * The file is capped (MAX_BYTES), the oldest sessions dropped first.
##
## Lines look like:   13:27:26.123 +0412.8s f=24711 [DEATH] p2 Pyro bot cell=(5, 3) ...
## (wall clock, seconds since start, frame number, tag). Use the tags consistently: they are what
## grep is for.

const PATH := "user://logs/bombardium.log"
const MAX_BYTES := 2_000_000
const KEEP_BYTES := 1_000_000
const SESSION_START := "=== SESSION START"
const SESSION_END := "=== SESSION END"
const HEARTBEAT_SECONDS := 10.0

var _file: FileAccess = null
var _mutex := Mutex.new()
var _logger: Logger = null
var _ended := false
var _previous_unclean := false

func _init() -> void:
	_open()
	_logger = _EngineLogger.new(self)
	OS.add_logger(_logger)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_write_header()
	if _previous_unclean:
		warn("SESSION", "the previous session did not end cleanly (crash, kill or power loss) — its last lines are above")
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var heartbeat := Timer.new()
	heartbeat.wait_time = HEARTBEAT_SECONDS
	heartbeat.autostart = true
	heartbeat.timeout.connect(_heartbeat)
	add_child(heartbeat)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			end_session("window close requested")
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			info("APP", "focus lost")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			info("APP", "focus regained")
		NOTIFICATION_APPLICATION_PAUSED:
			info("APP", "paused by the OS")
		NOTIFICATION_APPLICATION_RESUMED:
			info("APP", "resumed by the OS")

func _exit_tree() -> void:
	end_session("shutdown")
	if _logger != null:
		OS.remove_logger(_logger)

# --- Writing ------------------------------------------------------------------

func info(tag: String, message: String) -> void:
	_line(tag, message)

func warn(tag: String, message: String) -> void:
	_line(tag, "WARN " + message)

func error(tag: String, message: String) -> void:
	_line(tag, "ERROR " + message)

## "(5, 3)" — a cell, in the shape every line writes it.
static func cell(c: Vector2i) -> String:
	return "(%d, %d)" % [c.x, c.y]

## "p2 PYRO bot" / "p1 MINER kbd" / "p3 SCOUT pad0" — who a line is about, whatever calls it.
static func who(player_id: int, character_id: int, device: int) -> String:
	var key: String = Consts.CHARACTER_NAME_KEYS[character_id] if character_id >= 0 and character_id < Consts.CHARACTER_NAME_KEYS.size() else "CHAR_NAME_?"
	var dev := "bot" if device == Consts.DEVICE_BOT else ("kbd" if device == -1 else "pad%d" % device)
	return "p%d %s %s" % [player_id, key.trim_prefix("CHAR_NAME_"), dev]

## Same, from a Player node.
static func who_node(p: Node) -> String:
	if p == null or not is_instance_valid(p):
		return "p? (gone)"
	return who(p.player_id, p.character_id, p.device_id)

func end_session(reason: String) -> void:
	if _ended:
		return
	_ended = true
	_line("SESSION", "%s (%s)" % [SESSION_END + " ===", reason])

func _line(tag: String, message: String) -> void:
	_mutex.lock()
	if _file != null:
		var t := Time.get_datetime_dict_from_system()
		var ms := int(Time.get_unix_time_from_system() * 1000.0) % 1000
		_file.store_line("%02d:%02d:%02d.%03d +%07.1fs f=%d [%s] %s" % [
			t["hour"], t["minute"], t["second"], ms,
			Time.get_ticks_msec() / 1000.0, Engine.get_process_frames(), tag, message,
		])
		_file.flush()
	_mutex.unlock()

# --- Opening, trimming, and noticing a session that never finished ----------------

func _open() -> void:
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	if FileAccess.file_exists(PATH):
		var existing := FileAccess.get_file_as_string(PATH)
		_check_previous_session(existing)
		if existing.length() > MAX_BYTES:
			_trim(existing)
	_file = FileAccess.open(PATH, FileAccess.READ_WRITE if FileAccess.file_exists(PATH) else FileAccess.WRITE)
	if _file != null:
		_file.seek_end()

func _check_previous_session(text: String) -> void:
	var last_start := text.rfind(SESSION_START)
	if last_start < 0:
		return
	_previous_unclean = text.rfind(SESSION_END) < last_start

## Keeps the tail, from the start of a whole line.
func _trim(text: String) -> void:
	var tail := text.substr(text.length() - KEEP_BYTES)
	var cut := tail.find("\n")
	if cut >= 0:
		tail = tail.substr(cut + 1)
	var out := FileAccess.open(PATH, FileAccess.WRITE)
	if out != null:
		out.store_string(tail)
		out.close()

func _write_header() -> void:
	var exe := OS.get_executable_path()
	_line("SESSION", "%s ===" % SESSION_START)
	_line("SESSION", "build: %s, built %s, %s" % [
		ProjectSettings.get_setting("application/config/name", "?"),
		Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(exe)) if FileAccess.file_exists(exe) else "?",
		"debug" if OS.is_debug_build() else "release"])
	_line("SESSION", "engine: %s | os: %s %s | cpu: %s" % [
		Engine.get_version_info()["string"], OS.get_name(), OS.get_distribution_name(), OS.get_processor_name()])
	_line("SESSION", "gpu: %s | %s | renderer: %s" % [
		RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_api_version(),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")])
	_line("SESSION", "window: %s | locale: %s | args: %s" % [
		DisplayServer.window_get_size(), OS.get_locale(), " ".join(OS.get_cmdline_args())])
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		_line("PAD", "no pads connected")
	for device in pads:
		_line("PAD", "connected device=%d name=%s guid=%s" % [device, Input.get_joy_name(device), Input.get_joy_guid(device)])

# --- Things the Log watches on its own ---------------------------------------------

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var name := Input.get_joy_name(device) if connected else "-"
	_line("PAD", "%s device=%d name=%s" % ["connected" if connected else "DISCONNECTED", device, name])

## A line every few seconds: what a log of a slow death by memory or node count needs, and
## proof of when the game was last alive if it stops.
func _heartbeat() -> void:
	var scene := get_tree().current_scene
	_line("BEAT", "scene=%s fps=%d nodes=%d objects=%d mem=%.0fMB paused=%s" % [
		scene.name if scene != null else "-",
		Performance.get_monitor(Performance.TIME_FPS),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		get_tree().paused])

# --- The engine's own output, folded in -------------------------------------------

## print() and the engine's messages, and every error and warning with where it came from.
## Called from whichever thread produced the message, which is why _line takes a lock.
class _EngineLogger extends Logger:
	var _log: Node

	func _init(log_node: Node) -> void:
		_log = log_node

	func _log_message(message: String, is_error: bool) -> void:
		var text := message.strip_edges()
		if text.is_empty():
			return
		_log._line("STDERR" if is_error else "PRINT", text)

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
		var what := rationale if not rationale.is_empty() else code
		var text := "%s: %s  (%s:%d in %s)" % [kind, what, file, line, function]
		for trace in script_backtraces:
			text += "\n    " + trace.format().replace("\n", "\n    ")
		_log._line("ENGINE", text)
