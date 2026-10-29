# 《别炸我！》卡牌美术 v3 · 统一风格修订

## 交付内容

- 14 张牌面
- 1 张牌背
- 1 张整套总览图
- 单张 PNG 尺寸：1200 × 1800
- 设计尺寸：600 × 900（2 倍导出）
- 文件命名保持 Godot 友好，可直接导入

## 统一风格规则

这一轮修订保留原 v3 的主体识别度和分类颜色，但把所有卡牌重新整理成同一套视觉语言：

- 统一卡片圆角、双线外框、四角铆钉和米白纸质底色
- 统一标题、分类标签、分隔线、插画窗、规则文本和编号排版
- 统一插画窗尺寸、深色描边、金属高光、斜纹纸感和暗角
- 插画统一转为单色梯度处理，并按分类着色，减少原本绘画质感差异
- 工具牌统一提供 `×2`、`×3`、`5-1` 收集提示徽章
- 牌背使用同一版式语言，并改为深青 + 铜色工业牌背

## 分类颜色

| 分类 | 颜色 |
| --- | --- |
| 特殊牌 · 致命 | `#A32A20` |
| 特殊牌 · 保命 | `#20795F` |
| 行动牌 | `#31699A` |
| 反制牌 | `#6C539E` |
| 收集牌 · 工具族 | `#B26227` |
| 牌背 | `#22484B` |

## 文件

```text
png/
  card_bomb.png
  card_defuse.png
  card_skip.png
  card_attack.png
  card_peek.png
  card_shuffle.png
  card_steal.png
  card_overdraw.png
  card_nope.png
  card_tiger_pliers.png
  card_needle_pliers.png
  card_pipe_wrench.png
  card_cutter.png
  card_hydraulic.png
  card_back.png
card-ui-reference-overview.png
CODEX_REVIEW.md
```

## Godot 导入建议

- 作为普通 2D Texture 导入
- Filter：Linear
- Mipmaps：开启
- Compression：Lossless
- 覆盖 PNG 后在 Godot 中让资源重新导入
- 若用于高分辨率缩放，保留原始 1200 × 1800 文件
