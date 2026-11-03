# Assets 约定

2026-11-03用户确认正式复杂资源后置，先由代码生成像素示意支撑玩法；外部提示词保留但无需继续制作。现有人形样本可重复生成，仍遵守八向/非对称/共同动作合同，不把占位图称为正式美术。

> 先用占位验证玩法；素材制作按实际工作包推进。目录职责见[项目文件架构](../docs/PROJECT-STRUCTURE.md)。
> 新核查的素材/字体与许可流程见[完整资源研究](../design/research/full_game_reference_map.md)，Godot生态与具体音效/UI候选见[资源清单](../design/research/godot_resource_candidates.md)。正式批量资源在[长期方案](../docs/plans/full_game_program.md)玩法Alpha之后；开发中必要的可读反馈仍随玩法实现。

---

## 目录

下面是新增素材时的归属约定，按需要创建，不代表当前已有这些素材。多个场景共用的资源放这里；只属于某个场景的小资源可以就近保存。

```
assets/
├── art/
│   ├── characters/      # 玩家、Pawn、敌人
│   ├── tiles/           # TileSet、地形、建筑
│   ├── ui/              # 图标、面板、字体装饰
│   ├── fx/              # 特效、粒子贴图
│   └── world/           # 树、石头、装饰
├── audio/
│   ├── sfx/
│   ├── music/
│   └── ambience/
├── fonts/
└── third_party/         # 每个素材包一个目录 + LICENSE
```

---

## 命名

| 类型 | 前缀 | 示例 |
|---|---|---|
| 精灵 | `spr_` | `spr_pawn_cook.png` |
| 图块 | `tile_` | `tile_grass_01.png` |
| UI | `ui_` | `ui_panel_wood.png` |
| 图标 | `icon_` | `icon_wood.png` |
| 特效 | `fx_` | `fx_hit_spark.png` |
| 音效 | `sfx_` | `sfx_chop_01.ogg` |
| 音乐 | `mus_` | `mus_camp_day.ogg` |
| 环境 | `amb_` | `amb_forest.ogg` |

规则：
- 全小写 `snake_case`；不要空格/中文/大写。
- 同一类用两位序号：`_01`、`_02`。
- 变体用后缀：`_day`、`_night`、`_broken`。
- 不要用 `final`、`new`、`copy`、`v2` 这种命名。

---

## 导入设置

### 像素风（当前默认假设）
- Filter：**Nearest**
- Mipmaps：**Off**
- Compression：**Lossless**
- 像素网格对齐；不要缩放非整数倍。

### 手绘/高清（如果改方向）
- Filter：Linear
- Mipmaps：On（缩小显示时）
- 压缩：VRAM Compressed（注意色带）

### 音频
- SFX：`.ogg` 或 `.wav`（短音效用 wav 也可）
- Music：`.ogg`
- 统一采样率 44.1kHz/48kHz；不要在仓库放 192kHz 大文件。

### 字体
- 只放需要的字重/字符集。
- 开发期可用系统回退字体；独立包必须验证中文覆盖，不能直接拷贝系统字体分发。正式字体选有分发许可的确切版本，子集化也检查许可与保留字体名。
- 保留 OFL/LICENSE。

---

## 第三方素材

每个包：

```
assets/third_party/kenney_topdown/
├── LICENSE
├── SOURCE.md        # 链接、作者、下载日期、是否修改
└── ...素材
```

`SOURCE.md` 模板：

```markdown
- 名称：
- 作者：
- 链接：
- 许可证：
- 下载日期：
- 修改：
```

规则：
- 不把付费素材原样再分发。
- 不删除许可证。
- 不用来源不明的素材。
- AI 生成的素材记录工具/提示词/日期（可选，但建议）。

---

## 大文件

- 单文件 > 50MB：先问，必要时 Git LFS。
- 不提交原始 PSD/Blend/Aseprite 工程，除非需要协作；放 `art_source/` 并考虑 LFS。
- 不提交导出缓存、临时图、重复素材。

---

## 占位素材推荐

- **Kenney**：CC0，2D/3D/UI/音效，最适合占位。
- **LimeZu**：精致 2D，注意许可证/付费。
- **OpenGameArt**：混合许可，逐项检查。

先用纯色块也能做 M1；不要等美术。

## 当前八向样本与外部制作

原创代码生成的人形技术素材在[humanoid_sample](characters/humanoid_sample/README.md)，生成器与运行器合同已验但不是正式角色美术。用户外部模型使用[固定提示词包](../docs/art/character_generation/README.md)，原图先进入[候选接收区](../art_inbox/character_generation/README.md)，核方向/左右/alpha/脚点/来源及实机后才迁入发行素材。不覆盖已验技术样本、不从提示词推断已获得图像或商用授权。
