# @trace PLAT-002
## 联机协议（M2.1）：JSON 文本帧 over WebSocket。
## 客户端 → 服务器：hello / create / join / start / act / wish / leave
## 服务器 → 客户端：room_state / state / log / event / error
## 牌种类用 Card.Kind 的 int 值；座位号 seat = 房间内座次（0 起）。
class_name NetProtocol
extends RefCounted

# 客户端 → 服务器
const T_HELLO := "hello"
const T_CREATE := "create"
const T_JOIN := "join"
const T_START := "start"
const T_ACT := "act"
const T_WISH := "wish"
const T_LEAVE := "leave"

# 服务器 → 客户端
const T_ROOM_STATE := "room_state"
const T_STATE := "state"
const T_LOG := "log"
const T_EVENT := "event"
const T_ERROR := "error"
const T_RESPONSE_WINDOW := "response_window"
const T_FX := "fx"                 # 动作演出（服务器 → 客户端，纯表现、不参与规则）

# fx.fx 子类型（演出类型）
const FX_PLAY := "play"             # 打出功能牌进响应窗口（kind=牌种类）
const FX_DRAW := "draw"             # 抽牌（kind=牌种类，actor 本人可见牌面）
const FX_STEAL := "steal"           # 偷牌/对子盲偷（target=被偷者，牌面保密）
const FX_SHUFFLE := "shuffle"       # 洗牌
const FX_PEEK := "peek"             # 预知（仅本人看到结果弹窗，其他人只见横幅）
const FX_ATTACK := "attack"         # 攻击（下家多抽）
const FX_SKIP := "skip"             # 跳过
const FX_OVERDRAW := "overdraw"     # 进入透支连抽
const FX_OVERDRAW_STOP := "overdraw_stop"  # 喊停（count=收入张数）
const FX_FLUSH := "flush"           # 五张：从弃牌堆回收（kind=牌种类，公开）
const FX_DEFUSE := "defuse"         # 拆除爆弹成功
const FX_BOMB_PLACE := "bomb_place" # 暗置爆弹回牌堆
const FX_WISH := "wish"             # 休想反制成功

# 服务器事件子类型（event.e）
const E_BOMB := "bomb"             # name
const E_GAME_OVER := "game_over"   # winner
const E_PEEK := "peek"             # text（私有，仅发给打出者）
const E_CONNECTED := "connected"   # name（座位上线）
const E_OFFLINE := "offline"       # name（座位掉线）

# act.a 子类型
const A_DRAW := "draw"
const A_PLAY := "play"             # card[, target, wanted]（按牌种类分派）
const A_SINGLE := "single"         # card（单张工具打出）
const A_PLIERS := "pliers"         # cards[], combo, target, wanted
const A_BOMB := "bomb"             # pos
const A_FLUSH := "flush"           # idx
const A_OVERDRAW_DRAW := "overdraw_draw"
const A_OVERDRAW_STOP := "overdraw_stop"


static func encode(msg: Dictionary) -> String:
	return JSON.stringify(msg)


static func decode(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}
