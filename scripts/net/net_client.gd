# @trace PLAT-002
## 联机客户端网络层：WebSocketPeer 包装。
## 用法：add_child(NetClient.new()) → start("ws://...") → 等待 connected_ok → send()/received。
class_name NetClient
extends Node

signal connected_ok
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal received(msg: Dictionary)

enum NetState { OFF, CONNECTING, OPEN }

var state: NetState = NetState.OFF
var _peer: WebSocketPeer
var _url := ""


func start(url: String) -> void:
	close()
	_peer = WebSocketPeer.new()
	_url = url
	var err := _peer.connect_to_url(url)
	if err != OK:
		connection_failed.emit("连接地址无效: %s" % url)
		return
	state = NetState.CONNECTING


func send(msg: Dictionary) -> void:
	if state == NetState.OPEN and _peer != null:
		_peer.send_text(NetProtocol.encode(msg))


func close() -> void:
	if _peer != null:
		_peer.close()
	_peer = null
	state = NetState.OFF


func _process(_delta: float) -> void:
	if state == NetState.OFF or _peer == null:
		return
	_peer.poll()
	var ready_state := _peer.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN:
		if state == NetState.CONNECTING:
			state = NetState.OPEN
			connected_ok.emit()
		while _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			if _peer.was_string_packet():
				var msg := NetProtocol.decode(packet.get_string_from_utf8())
				if not msg.is_empty():
					received.emit(msg)
	elif ready_state == WebSocketPeer.STATE_CLOSED:
		var reason := _peer.get_close_reason()
		var was_connecting := state == NetState.CONNECTING
		_peer = null
		state = NetState.OFF
		if was_connecting:
			connection_failed.emit("连不上服务器：%s（确认服务器已启动）" % _url)
		else:
			disconnected.emit(reason)
