# @trace PLAT-002
## 房间管理器（M2.1）：创建/加入/清理，6 位数字邀请码。
class_name NetRoomManager
extends RefCounted

const MAX_ROOMS := 64

var _rooms: Dictionary = {}                 # code -> NetRoom
var _session_room: Dictionary = {}          # session_id -> code


func create_room(session_id: int, player_name: String, room_code: String) -> NetRoom:
	if _rooms.size() >= MAX_ROOMS:
		return null
	var room := NetRoom.new(room_code)
	room.host_session = session_id
	room.join(session_id, player_name)
	_rooms[room_code] = room
	_session_room[session_id] = room_code
	return room


## 加入房间；返回 (room, error)。error 为空串表示成功。
func join_room(session_id: int, player_name: String, room_code: String) -> Array:
	var room: NetRoom = _rooms.get(room_code, null)
	if room == null:
		return [null, "房间不存在，检查邀请码"]
	if room.started:
		return [null, "对局已开始，无法加入"]
	if room.is_full():
		return [null, "房间已满（最多 5 人）"]
	var seat := room.join(session_id, player_name)
	if seat < 0:
		return [null, "加入房间失败"]
	_session_room[session_id] = room_code
	return [room, ""]


func room_of_session(session_id: int) -> NetRoom:
	var code = _session_room.get(session_id, "")
	return _rooms.get(code, null) if code != "" else null


## 会话断开：座位标记掉线；房间无人则回收。
func session_offline(session_id: int) -> void:
	var room := room_of_session(session_id)
	if room == null:
		return
	var seat := room.seat_of(session_id)
	if seat >= 0:
		room.seats[seat] = -1   # 保留座位与名字（M2.3 将支持重连归位）
	_session_room.erase(session_id)


static func generate_code() -> String:
	return "%d" % [randi_range(100000, 999999)]
