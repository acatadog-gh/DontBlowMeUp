# 《别炸我！》Godot 工程骨架交付报告（M1 本地热座版）

日期：2026-10-28 ｜ 引擎：Godot 4.7.2 stable（官方 SHA256 校验通过：c58a24e3…）

## 为什么从 Unity 换到 Godot

1. Unity 国际版注册被 +86 手机号问题卡死；国内版团结引擎主线不明确
2. Godot 无需注册任何账号，开箱即用；用户核心诉求（卡牌 + 爆炸特效 + WebGL）全部覆盖
3. 核心玩法逻辑为纯逻辑代码，从 C# 1:1 移植到 GDScript，设计冻结条目全部保留 @trace 追踪
4. Unity 版工程保留在 `DontBlowMeUp/` 未删除，将来要回去也行

## 交付内容

- 工程骨架：`project.godot`（gl_compatibility 渲染器，WebGL 必需）+ `scenes/main.tscn`
- 核心逻辑 6 个 GDScript：Card / Deck / SeededRandom / GameConfig / PlayerState / TurnStateMachine
  - 全部数值来自 GameConfig（NUM-001/002），不硬编码
  - 状态机含：出牌/透支连抽/爆弹暗置/攻击叠层/弃牌重洗（MECH-011）/胜利判定（MECH-009）
- 热座 UI：`scripts/boot/main.gd`，程序化构建（开局面板 2-5 人、手牌点选、透支/喊停、偷牌选目标、爆弹暗置滑条、对局日志）
- 自检测试：`tests/run_tests.gd`，33 项断言

## 自检结果（真实运行输出）

33/33 全部通过，覆盖：
- 牌组构成 32 张明细（6/5/6/4/5/3/3）
- 发牌规则「每人 4 功能 + 1 拆除」
- MECH-011 弃牌堆重洗
- MECH-008 透支：喊停入手 / 抽中爆弹全弃（60 种子穷举覆盖爆弹分支）
- MECH-007 偷牌手牌守恒
- MECH-009：40 局自动对局（2-5 人 × 10 种子）全部收敛，终局唯一存活赢家，引爆爆弹数 = 玩家数 − 1

## 可复现验证方式

```bash
# 1. 自检测试（退出码 0 = 通过）
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --path DontBlowMeUp-Godot --import
/Applications/Godot.app/Contents/MacOS/Godot --headless \
  --path DontBlowMeUp-Godot -s res://tests/run_tests.gd

# 2. 打开编辑器实际游玩
open -a Godot        # 项目管理器 → 导入 DontBlowMeUp-Godot → F5 运行

# 3. 导出 WebGL（编辑器内一次性）
# 项目 → 导出 → 添加 Web → 导出项目，得到 index.html + .wasm，任意静态服务器可开
```

## 尚未完成（如实声明）

1. 特效与卡面美术：未开始（用户重点诉求，下一里程碑做 GPUParticles2D 爆炸特效）
2. WebGL 导出模板未下载（需在 Godot 编辑器里点一次下载，约 1 GB）
3. 单局时长实测（NUM-004，10-15 分钟）待真人试玩 3 局后校准
