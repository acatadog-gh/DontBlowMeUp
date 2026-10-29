# Codex 卡面素材 · Reference Set v1

## 交付内容
- 14 张功能牌面 + 1 张统一牌背，共 15 张 PNG。
- 另附 1 张总览图，便于快速审阅。
- 单卡画布：600 × 900（2:3）；导出为 2x，实际 PNG 为 1200 × 1800。
- 卡背与爆弹牌共用参考样张中的卡通炸弹插画；其他插画为代码绘制的卡通拟人 SVG。

## 文件
- `png/card_bomb.png`：爆弹
- `png/card_defuse.png`：拆除
- `png/card_skip.png`：跳过
- `png/card_attack.png`：攻击
- `png/card_peek.png`：预知
- `png/card_shuffle.png`：洗牌
- `png/card_steal.png`：偷牌
- `png/card_overdraw.png`：透支
- `png/card_nope.png`：休想
- `png/card_tiger_pliers.png`：老虎钳
- `png/card_needle_pliers.png`：尖嘴钳
- `png/card_pipe_wrench.png`：管钳
- `png/card_cutter.png`：断线钳
- `png/card_hydraulic.png`：液压钳
- `png/card_back.png`：统一牌背
- `card-ui-reference-overview.png`：整套总览

## 设计说明
- 版式参考用户提供的卡通样张：奶油纸卡面、彩色外框、居中标题、副标题、插画框、短描述。
- 分类色：
  - 爆弹 / 致命：`#A32A20`
  - 拆除 / 保命：`#20795F`
  - 行动牌：`#31699A`
  - 反制牌：`#6C539E`
  - 收集 / 工具族：`#B26227`
  - 牌背底色：`#22484B`
- 工具族插画右上角带 `×2`、`×3`、`5-1` 收集组合提示。
- 文案按 `docs/card-ui-brief.md` v0.9 的建议牌面描述排版。

## Godot 使用
- 可将 `png/` 内所有图片直接作为 `Texture2D` 导入。
- 建议卡牌节点按 600 × 900 的比例缩放；2x PNG 可保持清晰度。
