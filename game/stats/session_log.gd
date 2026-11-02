class_name SessionLog
extends RefCounted
## The log of one session for `StatsRecorder` (`stats/sessions/<date>_<time>.jsonl`: one JSON
## object per line, what happened when): each line says when (`t`, seconds into the session) and,
## during a run, which one and how far into it (`run`, `run_t`). Damage taken is merged per cause
## and second (`hurt`). It keeps the session's and the run's clocks (`tick`, `start_run`,
## `end_run`). Nothing waits for the disk: lines go through a buffer flushed every few seconds;
## the oldest logs beyond `KEEP_SESSIONS` are deleted when a session starts. Nothing is written
## without a folder (the tests).

const SESSIONS_FOLDER: String = "sessions"
## Session logs kept, the newest; older ones are deleted when a session starts.
const KEEP_SESSIONS: int = 20
## Seconds between writes of the buffer.
const FLUSH_INTERVAL: float = 5.0
## Damage taken from one cause within this many seconds is logged as one line.
const HURT_MERGE: float = 1.0

## Seconds since the session started, and since the run started (-1 while none is underway).
var time: float = 0.0
var run_time: float = -1.0
## Runs started this session.
var runs: int = 0

## The open file, or null while nothing is written.
var _file: FileAccess
var _since_flush: float = 0.0
## Damage taken not logged yet, per cause: {amount, hits, t}.
var _hurts: Dictionary[String, Dictionary] = {}


## Opens this session's log in `directory`/`SESSIONS_FOLDER` (nothing without one), deleting the
## oldest ones beyond `KEEP_SESSIONS`.
func open(directory: String) -> void:
	if not directory:
		return
	var sessions: String = directory.path_join(SESSIONS_FOLDER)
	DirAccess.make_dir_recursive_absolute(sessions)
	var logs: Array[String] = []
	for file: String in DirAccess.get_files_at(sessions):
		if file.ends_with(".jsonl"):
			logs.append(file)
	logs.sort()
	while logs.size() >= KEEP_SESSIONS:
		var oldest: String = logs.pop_front()
		DirAccess.remove_absolute(sessions.path_join(oldest))
	var stamp: String = Time.get_datetime_string_from_system().replace("T", "_").replace(":", "-")
	var path: String = sessions.path_join(stamp + ".jsonl")
	_file = FileAccess.open(path, FileAccess.WRITE)
	if not _file:
		push_error("Stats: can't write %s (%s)" % [path, error_string(FileAccess.get_open_error())])


## Whether it's open (lines are written).
func is_open() -> bool:
	return _file != null


## Moves the clocks on by `delta` s, logs the damage merged long enough and writes the buffer now
## and then.
func tick(delta: float) -> void:
	time += delta
	if in_run():
		run_time += delta
	log_hurts(false)
	_since_flush += delta
	if _since_flush >= FLUSH_INTERVAL:
		_since_flush = 0.0
		flush()


## A run starts: its clock and number.
func start_run() -> void:
	runs += 1
	run_time = 0.0


## The run is over (lines carry no run any more).
func end_run() -> void:
	run_time = -1.0


## Whether a run is underway.
func in_run() -> bool:
	return run_time >= 0.0


## Logs `event` with `fields`, when it happened (`at`: seconds into the session; now by default)
## and in which run (with its time) while one is underway.
func write(event: String, fields: Dictionary, at: float = -1.0) -> void:
	if not _file:
		return
	var line: Dictionary = {"t": snappedf(time if at < 0.0 else at, 0.01), "e": event}
	if in_run():
		line["run"] = runs
		line["run_t"] = snappedf(run_time - (time - at if at >= 0.0 else 0.0), 0.01)
	line.merge(fields)
	_file.store_line(JSON.stringify(line, "", false))


## Damage taken from `cause` (a label): merged with what came from it within `HURT_MERGE` s.
func hurt(cause: String, amount: float) -> void:
	var pending: Dictionary = _hurts.get_or_add(cause, {"amount": 0.0, "hits": 0, "t": time})
	pending["amount"] += amount
	pending["hits"] += 1


## Logs the damage taken per cause that's older than `HURT_MERGE` (`all`: all of it).
func log_hurts(all: bool = true) -> void:
	for label: String in _hurts.keys():
		var pending: Dictionary = _hurts[label]
		var since: float = pending["t"]
		if all or time - since >= HURT_MERGE:
			var amount: float = pending["amount"]
			write(
				"player_hurt",
				{"cause": label, "amount": snappedf(amount, 0.01), "hits": pending["hits"]},
				since
			)
			_hurts.erase(label)


## Writes what the buffer holds back (the tests read it right away).
func flush() -> void:
	if _file:
		_file.flush()


## Logs the damage still merging and closes the file.
func close() -> void:
	if not _file:
		return
	log_hurts()
	_file.close()
	_file = null
