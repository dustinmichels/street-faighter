class_name PortMapper
extends Node
## Asks the router to forward a UDP port to this computer (UPnP) while
## `Session` hosts, so an opponent on the internet can join the INTERNET
## address without manual port forwarding. Talking to the router takes up to
## a few seconds, so it runs on worker threads; `finished` reports each
## `open()` on the main thread. The mapping is removed when hosting stops
## (`close()`) or the game quits, and it expires after `LEASE_SECONDS`
## anyway, so a crash can't leave it open for good.

## Outcome of `open()`.
enum Result {
	## The router forwards the port.
	OPENED,
	## A router answered, but its own internet address is private
	## (carrier-grade NAT, or a second router in front of it), so
	## forwarding can't make the INTERNET address reach this computer.
	## miniupnpc reports such a router as disconnected
	## (`IGD_STATUS_DISCONNECTED`) and maps no ports on it.
	BEHIND_NAT,
	## No UPnP router answered: UPnP is off or unsupported.
	NO_ROUTER,
	## The router answered but refused, e.g. the port is already forwarded
	## to another computer.
	REFUSED,
}

## The router's answer for `port`, the port of the latest `open()`.
signal finished(port: int, result: Result)

## How long discovery waits for routers to answer, per search: miniupnpc
## searches for up to 4 device types in turn, with at least 1 s each, so
## with no UPnP router discovery takes ~4 s. Quitting the game waits for a
## discovery in progress (the engine joins the worker threads on exit).
const DISCOVER_TIMEOUT_MS := 1000
## Lease of a mapping (s). Routers that only take permanent ones get a
## permanent one, which `close()` removes.
const LEASE_SECONDS := 4 * 60 * 60
## Shown in the router's list of forwarded ports.
const DESCRIPTION := "street-faighter"

## Off: `open()` does nothing (no router traffic). Off with the `--no-upnp`
## user argument, for local testing; tests may also set it.
var enabled := "--no-upnp" not in OS.get_cmdline_user_args()
## The port to forward (`open()`), 0 = none (`close()`). Set on the main
## thread, read by workers, so guarded by `_want_mutex`.
var _want := 0
var _want_mutex := Mutex.new()
## Serializes the workers, which alone use the fields below: the router
## holding the mapping, its port (0 = none) and the last `open()` result.
var _work_mutex := Mutex.new()
var _upnp: UPNP
var _mapped := 0
var _result := Result.NO_ROUTER
## Worker tasks not yet waited for.
var _tasks: Array[int] = []


## Forwards UDP `port` to this computer (replacing an earlier mapping), then
## emits `finished`. Does nothing unless `enabled`.
func open(port: int) -> void:
	if enabled:
		_set_want(port)


## Removes the mapping, if any.
func close() -> void:
	_set_want(0)


## On quit: removes the mapping. A discovery in progress can't be cancelled
## and the engine waits for it (up to ~4 s), so the window is minimized
## first (the main window can't be hidden) and the quit looks instant.
func _exit_tree() -> void:
	close()
	if _tasks.any(
		func(id: int) -> bool:
			return not WorkerThreadPool.is_task_completed(id),
	):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _set_want(port: int) -> void:
	_want_mutex.lock()
	var changed := _want != port
	_want = port
	_want_mutex.unlock()
	if not changed:
		return
	var running: Array[int] = []
	for id in _tasks:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			running.append(id)
	_tasks = running
	_tasks.append(WorkerThreadPool.add_task(_sync_mapping))


func _wanted() -> int:
	_want_mutex.lock()
	var port := _want
	_want_mutex.unlock()
	return port


## Worker: brings the router in line with `_want` and reports the result.
## Workers may run in any order; each one applies the latest `_want`.
func _sync_mapping() -> void:
	_work_mutex.lock()
	var want := _wanted()
	if _mapped != want:
		_unmap()
		if want != 0:
			_result = _map(want)
	var result := _result
	_work_mutex.unlock()
	if want != 0:
		_report.call_deferred(want, result)


func _map(port: int) -> Result:
	var upnp := UPNP.new()
	if upnp.discover(DISCOVER_TIMEOUT_MS) != UPNP.UPNP_RESULT_SUCCESS:
		return Result.NO_ROUTER
	var result := Result.NO_ROUTER
	for i in upnp.get_device_count():
		var device := upnp.get_device(i)
		if device.is_valid_gateway():
			result = Result.OPENED
			break
		if device.igd_status == UPNPDevice.IGD_STATUS_DISCONNECTED:
			result = Result.BEHIND_NAT
	if result != Result.OPENED:
		return result
	var err := upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", LEASE_SECONDS)
	if err == UPNP.UPNP_RESULT_ONLY_PERMANENT_LEASE_SUPPORTED:
		err = upnp.add_port_mapping(port, port, DESCRIPTION, "UDP", 0)
	if err != UPNP.UPNP_RESULT_SUCCESS:
		return Result.REFUSED
	_upnp = upnp
	_mapped = port
	return Result.OPENED


func _unmap() -> void:
	if _mapped != 0:
		_upnp.delete_port_mapping(_mapped, "UDP")
	_upnp = null
	_mapped = 0


## Main thread: emits `finished` unless the port changed meanwhile.
func _report(port: int, result: Result) -> void:
	if port == _wanted():
		finished.emit(port, result)
