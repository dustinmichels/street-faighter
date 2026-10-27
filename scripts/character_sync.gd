class_name CharacterSync
extends Node
## Online character exchange (`docs/todo/custom-characters.md` §7), a child of
## the `Session` autoload so it outlives match scenes.
##
## After the handshake each side announces its character
## (`CharacterLibrary.descriptor()`, `announce()`). A custom character this
## machine doesn't have (no library entry, no cached download) is requested
## from its owner (`fetch()`), who sends its `.glb` in chunks of at most
## `CHUNK_BYTES` on `TRANSFER_CHANNEL`, its own reliable channel, so a
## transfer doesn't hold up the session's messages on channel 0 or the
## inputs on channel 1. The size comes from the descriptor, which is checked
## against `CharacterValidator.MAX_FILE_BYTES` before a request is sent, and
## no chunk past it is accepted. The finished file must match its SHA-256 and
## pass the full `CharacterValidator`; it is then cached as
## `CharacterLibrary.remote_path()`, so later matches reuse it.

## The peer's first announcement arrived (`peer_character`).
signal peer_announced
## A download ended: `ok` if the character is now cached.
signal fetched(id: String, ok: bool)

## Largest chunk per RPC.
const CHUNK_BYTES := 64 * 1024
## `SceneMultiplayer` transfer channel of the chunks (`InputSync` uses 1).
const TRANSFER_CHANNEL := 2

## The other player's multiplayer peer id; 0 when not connected.
var peer_id := 0
## This machine's / the peer's announced character (`descriptor()`).
var own_character := {}
var peer_character := {}
## Downloads by sha256: `{size, bytes, state}`, `state` one of "receiving",
## "ready", "failed". A failed one isn't requested again this session.
var _downloads := {}
## Characters already sent to the peer (each at most once per session).
var _sent := {}


## Back to no session: forgets the announcements and unfinished downloads.
func reset() -> void:
	peer_id = 0
	own_character = {}
	peer_character = {}
	_downloads = {}
	_sent = {}


## Tells the peer which character this machine plays (`desc`, a
## `CharacterLibrary.descriptor()`).
func announce(desc: Dictionary) -> void:
	own_character = desc
	_announce_rpc.rpc_id(peer_id, desc)


## Where the character `desc` stands on this machine: "ready" (a built-in, a
## library entry or a cached download; also for malformed descriptors, which
## mean the default), "receiving", or "failed" (the download was rejected).
## Calls `fetch()` first, so a missing character starts downloading.
func status(desc: Variant) -> String:
	fetch(desc)
	var id := CharacterLibrary.descriptor_sha256(desc)
	if id.is_empty() or not _downloads.has(id):
		return "ready"
	return _downloads[id].state


## Requests `desc`'s `.glb` from the peer if it names a custom character this
## machine doesn't have and hasn't requested yet. Only the peer's own
## announced character can be requested. Nothing is downloaded while
## `CharacterLibrary.opponents_default()` is on.
func fetch(desc: Variant) -> void:
	var id := CharacterLibrary.descriptor_sha256(desc)
	if id.is_empty() or _downloads.has(id) or not CharacterLibrary.descriptor_model(desc).is_empty() \
			or CharacterLibrary.opponents_default():
		return
	if id != CharacterLibrary.descriptor_sha256(peer_character) or peer_id == 0:
		_downloads[id] = {"size": 0, "bytes": PackedByteArray(), "state": "failed"}
		fetched.emit(id, false)
		return
	_downloads[id] = {"size": int(desc.size), "bytes": PackedByteArray(), "state": "receiving"}
	_request_rpc.rpc_id(peer_id, id)


@rpc("any_peer", "call_remote", "reliable")
func _announce_rpc(desc: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != peer_id or not peer_character.is_empty():
		return
	peer_character = CharacterLibrary.clean_descriptor(desc)
	fetch(peer_character)
	peer_announced.emit()


## The peer asks for this machine's character `id`: sends it in chunks.
@rpc("any_peer", "call_remote", "reliable")
func _request_rpc(id: String) -> void:
	if multiplayer.get_remote_sender_id() != peer_id or _sent.has(id) \
			or id != CharacterLibrary.descriptor_sha256(own_character):
		return
	_sent[id] = true
	var bytes := FileAccess.get_file_as_bytes(CharacterLibrary.glb_path(id))
	if bytes.is_empty():
		push_warning("CharacterSync: can't read character %s to send it" % id)
		return
	for offset in range(0, bytes.size(), CHUNK_BYTES):
		_chunk_rpc.rpc_id(peer_id, id, offset, bytes.slice(offset, offset + CHUNK_BYTES))


@rpc("any_peer", "call_remote", "reliable", TRANSFER_CHANNEL)
func _chunk_rpc(id: String, offset: int, chunk: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != peer_id or not _downloads.has(id):
		return
	var download: Dictionary = _downloads[id]
	if download.state != "receiving":
		return
	var bytes: PackedByteArray = download.bytes
	if offset != bytes.size() or chunk.is_empty() or chunk.size() > CHUNK_BYTES \
			or bytes.size() + chunk.size() > download.size:
		_finish(id, "chunk at %d (%d bytes) doesn't fit the announced %d bytes" % [offset, chunk.size(), download.size])
		return
	download.bytes = PackedByteArray()  # so the append below doesn't copy
	bytes.append_array(chunk)
	download.bytes = bytes
	if bytes.size() == download.size:
		_finish(id, _store(id, bytes))


## Checks and caches a complete download, returning the problem ("" = cached).
func _store(id: String, bytes: PackedByteArray) -> String:
	if CharacterLibrary.sha256(bytes) != id:
		return "SHA-256 mismatch"
	var path := CharacterLibrary.remote_path(id)
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return "can't create '%s': %s" % [path.get_base_dir(), error_string(err)]
	# Validated under a temporary name, so the cache only ever holds checked files.
	var temp := path.get_basename() + ".part.glb"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "can't write '%s': %s" % [temp, error_string(FileAccess.get_open_error())]
	file.store_buffer(bytes)
	file.close()
	var validator := CharacterValidator.new()
	var errors := validator.validate(temp)
	if validator.scene != null:
		validator.scene.free()
	if not errors.is_empty():
		DirAccess.remove_absolute(temp)
		return "invalid character: %s" % "; ".join(errors)
	err = DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
		return "can't save '%s': %s" % [path, error_string(err)]
	return ""


func _finish(id: String, problem: String) -> void:
	var download: Dictionary = _downloads[id]
	download.bytes = PackedByteArray()
	download.state = "ready" if problem.is_empty() else "failed"
	if not problem.is_empty():
		push_warning("CharacterSync: rejected the opponent's character %s: %s" % [id, problem])
	fetched.emit(id, problem.is_empty())
