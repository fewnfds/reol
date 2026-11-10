# 八方向纸娃娃：每个提示词文件只生成一张图

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../../README.md)。归档于2026-11-11。

**当前已后置（2026-11-03用户决定）：暂不制作复杂正式美术，开发侧用代码生成像素示意图支撑玩法。此目录保留为未来素材生产资料，用户现在无需继续生成、修正或交齐动作。** 八方向/左右/共同相位的技术合同保留，不能把占位图当正式美术验收。

2026-11-03按网页模型用法修订。**不需要agent、不需要模型读文件、不需要八方向分八次。** 当前目录的编号文件均为“一份文件＋实际上传的参考附件→一张图片”；每份只有一个可复制文本框，包含完整规格。索引和验收资料不需要粘贴给模型。

**已有第一张候选时，先用[14：镜头与占比修正](14_base_camera_fix_eight.md)。** 用户返回的八向JPG可作为人物身份参考，但俯角和格内大小尚未通过，不据它批量生成衣服和动作。尚未开始的用户从[01：基础衣母版八向表](01_base_eight.md)开始；每次都是4列×2行八方向一张图。

使用方法：打开一份编号文件→按文件开头上传前置参考图→复制唯一文本框→只生成一张→按建议图片名保存。网页每次不记得之前内容也没关系，所有固定约束都已在每份正文重述。文件名只是让你匹配上传附件；不要求模型自动寻找文件。

| 提示词文件 | 本次唯一输出 | 需要实际上传的前置图 |
|---|---|---|
| [01_base_eight.md](01_base_eight.md) | `reol_base_eight.png` | 无 |
| [02_robe_composite_eight.md](02_robe_composite_eight.md) | `reol_robe_composite_eight.png` | `reol_base_eight.png` |
| [03_robe_layer_eight.md](03_robe_layer_eight.md) | `reol_robe_layer_eight.png` | `reol_base_eight.png`、`reol_robe_composite_eight.png` |
| [04_hat_composite_eight.md](04_hat_composite_eight.md) | `reol_hat_composite_eight.png` | `reol_robe_composite_eight.png` |
| [05_hat_layer_eight.md](05_hat_layer_eight.md) | `reol_hat_layer_eight.png` | `reol_base_eight.png`、`reol_hat_composite_eight.png` |
| [06_sword_jade_composite_eight.md](06_sword_jade_composite_eight.md) | `reol_sword_jade_composite_eight.png` | `reol_robe_composite_eight.png` |
| [07_sword_layer_eight.md](07_sword_layer_eight.md) | `reol_sword_layer_eight.png` | `reol_sword_jade_composite_eight.png` |
| [08_jade_layer_eight.md](08_jade_layer_eight.md) | `reol_jade_layer_eight.png` | `reol_sword_jade_composite_eight.png` |
| [09_cape_composite_eight.md](09_cape_composite_eight.md) | `reol_cape_composite_eight.png` | `reol_robe_composite_eight.png` |
| [10_cape_layer_eight.md](10_cape_layer_eight.md) | `reol_cape_layer_eight.png` | `reol_base_eight.png`、`reol_cape_composite_eight.png` |
| [11_base_walk_keys.md](11_base_walk_keys.md) | `reol_base_walk_keys.png` | `reol_base_eight.png` |
| [12_base_idle_keys.md](12_base_idle_keys.md) | `reol_base_idle_keys.png` | `reol_base_eight.png` |
| [13_base_gesture_keys.md](13_base_gesture_keys.md) | `reol_base_gesture_keys.png` | `reol_base_eight.png` |
| [14_base_camera_fix_eight.md](14_base_camera_fix_eight.md) | `reol_base_eight_corrected.png` | 刚返回的旧八向JPG，仅作身份参考 |

01–10是八方向站姿：每张1024×512、4列2行，方向顺序`N NE E SE / S SW W NW`；每格256×256，人物根(128,174)。11–13是**站姿验收之后**的四关键相位参考：每张1024×2048、4列8行；四列为相位、八行为方向，不是完整16帧动画。

第一轮优先01、02、03、06、07、08，即母体、一件常服、左手剑/右腰玉佩；帽子04/05和蓑衣09/10可稍后。这些都各有独立文件，不要求一次做整包。

14修正通过后，把选定的原始PNG作为后续所需的`reol_base_eight.png`附件（仅交付命名，不要求模型自己读取/更名）；旧草稿单独保留。只改名不能代替实际镜头验收。画风目前为简洁手绘候选，像素风尚未由用户定稿，像素化不能修复错误俯角。站姿和完整动画的区别、奔跑/冲刺/受击/倒地/起身等后续覆盖见[动作说明](guides/action_coverage.md)。

**基础选择：** 成年人穿贴身短衣短裤与基础布鞋作为母体，不需要全裸。衣帽/剑佩/蓑衣分别交“完整人物合成表”和“独立完整图层表”；两种输出在不同文件里，不在一条提示词里要求同时产出两张图。独立源层之后还要人工制作/核对遮挡，不能只从合成图抠可见碎片冒充完整可换装资产。隐藏内容只能补成合理候选，返回后会核对，不承诺提示词能自动保证叠合。持剑展示允许左手手指合拢，开发侧还需制作对应持物手局部变体/遮罩；这项不要求你另外生成图片。

[验收与回传](guides/acceptance_and_return.md)记录怎样交原PNG、实际提示词、模型/seed如可见、已知问题和来源。[Godot商店/资产库研究](guides/godot_options.md)是选型资料，不需要发给图像模型，没有安装候选插件。

候选原图可放[art_inbox](../../../../art_inbox/character_generation/README.md)，或在聊天中返回；不覆盖现有技术图集。之前逐向/多段提示词完整保存在[旧版归档](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/character_generation_prompts_20261103_early/README.md)，本次起只用当前编号文件。
