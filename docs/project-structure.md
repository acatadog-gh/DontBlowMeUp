# 《别炸我！》Godot 工程目录结构

> 引擎：Godot 4.7.2 stable（无需账号，免费开源，MIT 协议）

```
DontBlowMeUp-Godot/
├── project.godot            # 工程配置（gl_compatibility 渲染，WebGL 导出必需）
├── scenes/
│   └── main.tscn            # 主场景（热座对局入口）
├── scripts/
│   ├── core/                # 与引擎无关的核心逻辑
│   │   ├── card.gd          #   卡牌定义（7 种牌型）        @trace MECH-001
│   │   ├── deck.gd          #   牌池/弃牌堆/重洗/暗置      @trace MECH-002, 011
│   │   └── random_service.gd#   可种子化随机源（可复现测试）
│   ├── data/
│   │   └── game_config.gd   # 全部数值集中于此，不写死在玩法里 @trace NUM-001/002
│   ├── gameplay/
│   │   ├── player_state.gd  #   玩家状态（手牌/透支区/存活）
│   │   └── turn_state_machine.gd # 回合状态机（核心中的核心）@trace MECH-003~009
│   ├── boot/
│   │   └── main.gd          # 热座 UI（开局面板/手牌/透支/暗置爆弹/日志）@trace UI-001
│   └── tests → 见根目录 tests/
├── tests/
│   └── run_tests.gd         # 无头自检：33 项断言，覆盖全部冻结条目
└── docs/
    ├── design-freeze.json   # 设计冻结清单（与策划案同步，status=frozen）
    ├── gdd-draft-v1.md      # 策划案 v0.4
    ├── project-structure.md # 本文件
    └── godot-scaffold-report.md # 交付报告与验证方式
```

## 与 Unity 版的对应关系

| Unity 版（已归档） | Godot 版 | 说明 |
|---|---|---|
| Assets/Scripts/Core/*.cs | scripts/core/*.gd | 逻辑 1:1 移植 |
| Assets/Scripts/Data/GameConfig.cs | scripts/data/game_config.gd | ScriptableObject → RefCounted |
| Assets/Scripts/Gameplay/TurnStateMachine.cs | scripts/gameplay/turn_state_machine.gd | C# event → GDScript signal |
| Assets/Scripts/UI/HudView.cs（IMGUI） | scripts/boot/main.gd（Control 树） | UI 层按引擎习惯重写 |
| Assets/Scripts/Editor/*.cs（场景生成） | 不需要 | .tscn 文本格式直接落盘 |

## 后续内容放在哪

- 卡面/特效资源 → 新建 `assets/` 目录（图片放 `assets/art/`，场景特效直接在 .tscn 里加 GPUParticles2D）
- 音效 → `assets/audio/`
- WebGL 导出预设 → 编辑器里 项目 → 导出 → 添加 Web 导出（首次需在编辑器里下载导出模板）
