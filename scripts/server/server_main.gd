# @trace PLAT-002
## 《别炸我！》专用服务器（M2.1/M2.2）：无头运行。
## 启动：Godot --headless --path 工程目录 -s scripts/server/server_main.gd -- port=8920
## 架构：TCPServer 监听 → 每连接一个 WebSocketPeer.accept_stream → JSON 文本帧 → 房间分发。
## 房间逻辑全部在 NetRoom/NetRoomManager（可无头单测），本文件只做收发与路由。
extends SceneTree

const DEFAULT_PORT := 8920
const ROOM_CODE_RECYCLE := false   # M2.3 重连上线前：房间空了就回收

var _tcp: TCPServer
var _port := DEFAULT_PORT
var _sessions: Dictionary = {}     # session_id -> {peer: WebSocketPeer, name: String}
var _next_session := 1
var _manager := NetRoomManager.new()


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("port="):
			_port = int(arg.split("=")[1])
	_tcp = TCPServer.new()
	var err := _tcp.listen(_port, "0.0.0.0")
	if err != OK:
		print("[server] 监听失败 port=%d err=%d" % [_port, err])
		quit(1)
		return
	seed(int(Time.get_unix_time_from_system()))
	print("[server] 别炸我！服务器已启动 ws://0.0.0.0:%d" % _port)


func _process(_delta: float) -> bool:
	# Godot 4.x：TCPServer 自动轮询，无需手动 poll
	while _tcp.is_connection_available():
		var session_id := _next_session
		_next_session += 1
		var peer := WebSocketPeer.new()
		peer.accept_stream(_tcp.take_connection())
		_sessions[session_id] = {"peer": peer, "name": ""}
		print("[server] 新连接 #%d" % session_id)

	var now_ms := Time.get_ticks_msec()
	for session_id in _sessions.keys():
		var session: Dictionary = _sessions[session_id]
		var peer: WebSocketPeer = session.peer
		peer.poll()
		var state := peer.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			while peer.get_available_packet_count() > 0:
				var packet := peer.get_packet()
				if peer.was_string_packet():
					var msg := NetProtocol.decode(packet.get_string_from_utf8())
					if not msg.is_empty():
						_dispatch(session_id, msg, now_ms)
		elif state == WebSocketPeer.STATE_CLOSED:
			_on_session_closed(session_id)

	for room in _manager._rooms.values():
		room.tick(float(now_ms))
	return false


func _dispatch(session_id: int, msg: Dictionary, now_ms: float) -> void:
	var t: String = msg.get("t", "")
	var session: Dictionary = _sessions[session_id]
	match t:
		NetProtocol.T_HELLO:
			session["name"] = String(msg.get("name", "玩家")).left(8)
			_send(session_id, {"t": NetProtocol.T_EVENT, "e": "welcome", "name": session["name"]})
		NetProtocol.T_CREATE:
			if _manager.room_of_session(session_id) != null:
				_send(session_id, {"t": NetProtocol.T_ERROR, "msg": "你已在房间中"})
				return
			var room := _manager.create_room(session_id, session["name"],
					NetRoomManager.generate_code())
			if room == null:
				_send(session_id, {"t": NetProtocol.T_ERROR, "msg": "服务器房间已满，稍后再试"})
				return
			print("[server] 房间 %s 由 #%d 创建" % [room.code, session_id])
			_inject_callables(room)
			_broadcast_room_state(room)
		NetProtocol.T_JOIN:
			var result := _manager.join_room(session_id, session["name"], String(msg.get("code", "")))
			var room: NetRoom = result[0]
			if room == null:
				_send(session_id, {"t": NetProtocol.T_ERROR, "msg": result[1]})
				return
			print("[server] #%d 加入房间 %s（座位 %d）" % [session_id, room.code, room.seat_of(session_id)])
			_inject_callables(room)
			# 房间状态广播给全房间：房主的"开始"按钮依赖人数刷新
			_broadcast_room_state(room)
		NetProtocol.T_START:
			var room := _manager.room_of_session(session_id)
			if room == null or room.started:
				return
			if room.host_session != session_id:
				_send(session_id, {"t": NetProtocol.T_ERROR, "msg": "只有房主能开始游戏"})
				return
			if room.start_game(int(Time.get_unix_time_from_system())):
				print("[server] 房间 %s 开局（%d 人）" % [room.code, room.connected_count()])
		NetProtocol.T_ACT, NetProtocol.T_WISH:
			var room := _manager.room_of_session(session_id)
			if room == null or not room.started:
				return
			var seat := room.seat_of(session_id)
			if seat < 0:
				return
			room.handle(seat, msg, float(now_ms))
		NetProtocol.T_LEAVE:
			_on_session_closed(session_id)
		_:
			_send(session_id, {"t": NetProtocol.T_ERROR, "msg": "未知消息类型"})


func _on_session_closed(session_id: int) -> void:
	var session: Dictionary = _sessions.get(session_id, {})
	var room := _manager.room_of_session(session_id)
	if room != null:
		var seat := room.seat_of(session_id)
		_manager.session_offline(session_id)
		if seat >= 0:
			room.send_all.call(NetProtocol.encode({
				"t": NetProtocol.T_EVENT, "e": NetProtocol.E_OFFLINE, "name": room.seat_names[seat]}))
			if room.started:
				room.broadcast_view()
			else:
				_broadcast_room_state(room)
		print("[server] #%d（%s）断开于房间 %s" % [session_id, session.get("name", "?"), room.code])
		if not ROOM_CODE_RECYCLE and room.connected_count() == 0:
			_manager._rooms.erase(room.code)
			print("[server] 房间 %s 空置回收" % room.code)
	else:
		_manager.session_offline(session_id)
	_sessions.erase(session_id)


func _send(session_id: int, msg: Dictionary) -> void:
	var session: Dictionary = _sessions.get(session_id, null)
	if session == null:
		return
	var peer: WebSocketPeer = session["peer"]
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(NetProtocol.encode(msg))


func _send_seat(room: NetRoom, seat: int, text: String) -> void:
	var session_id: int = room.seats[seat]
	if session_id >= 0 and _sessions.has(session_id):
		var peer: WebSocketPeer = _sessions[session_id]["peer"]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			peer.send_text(text)


func _send_all_room(room: NetRoom, text: String) -> void:
	for seat in room.seats.size():
		_send_seat(room, seat, text)


## 房间状态广播给全房间在线座位（建房/加入/掉线时刷新人数与房主标记）。
func _broadcast_room_state(room: NetRoom) -> void:
	for i in room.seats.size():
		if room.seats[i] >= 0:
			_send_room_state(room, room.seats[i])


func _send_room_state(room: NetRoom, to_session: int) -> void:
	var players: Array = []
	for i in room.seat_names.size():
		players.append({"name": room.seat_names[i], "seat": i,
				"host": room.seats[i] == room.host_session, "on": room.seats[i] >= 0})
	_send(to_session, {"t": NetProtocol.T_ROOM_STATE, "code": room.code,
			"you": room.seat_of(to_session), "players": players, "started": room.started})


## 给房间注入收发回调（房间本身不接触 socket）。
func _inject_callables(room: NetRoom) -> void:
	room.send_seat = func(seat: int, text: String) -> void: _send_seat(room, seat, text)
	room.send_all = func(text: String) -> void: _send_all_room(room, text)
