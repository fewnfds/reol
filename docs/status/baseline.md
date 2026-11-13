# 当前运行基线

更新：2026-11-13。本页只保留当前构建、有效证据和已知限制。能力查[FEATURES](features.md)，运行接口查[架构](../engineering/architecture.md)。

## 当前构建

Godot 4.7.2 stable（ed1daf0bf），GDScript，Windows release，D3D12 Forward+，1280×720，无VSync。正式入口scenes/main.tscn，独立包build/windows/reol-demo.exe及同目录pck；源码试玩和导出快照的差别见[usage](../engineering/tooling/usage.md)。

人物/装备/背包版由02958cc提交对应，PCK指纹、开发机与各倍率历史样本统一记录在[performance.json](performance.json)。它是工具可直接读取的数值原件，包含实际倍率而非倍率达成比例；本机原始报告在logs/capacity-20261113-shipped/。不要求新机器拥有这些日志才能接手。

## 已接受测量与验证

历史capacity-v1测量包含真实生活、房间、植物、环境、固定交战与施工群，零死亡且物资守恒。它用于后续同负载性能对照，不是全员同时交战或所有未来内容的普遍上限。采样/判据与工具入口见[usage](../engineering/tooling/usage.md#功能性能对照)。

人物换装的真实属性、原子转移、候选恢复和NPC只读交互已通过相关短检查；证据在logs/ui-smoke/与logs/smoke-20261113-222841-372329000.log。旧容量报告完成了19个窗口，仍保留作历史参考；今后的验证强度只查开发循环。

工具精简后以同一包的900人/4×历史配置做25秒复核，真实窗口通过；该次步均较历史约−4.4%，运行代码未改，只视为短窗波动，不替换已接受基线。证据在logs/performance-workflow-20261113-verified/；首个窗口因工具精确比较镜头浮点数被误判失效，已修复容差并补短反例，本次该倍率共运行2次，没有扩测其他倍率。

## 已知限制

- 满帧率不等于满世界倍率；高倍速首先可能达到模拟吞吐上限。降低渲染帧率不能保证解除模拟瓶颈。
- 既有移动/探索过程曾出现帧时尖峰，不能据静止玩家的好窗宣称所有场景锁帧。
- 目标16GB/RTX3060整机、长局、极密战斗/拆建、远区LOD未由上述样本验证。

## 历史追溯

历轮版本、失败实验、方向/素材/导航/视野对照均可从[整理前基线](https://github.com/fewnfds/reol/blob/02958cc/docs/status/baseline.md)和本机logs追溯。更早调查见[archive](../archive/README.md)；旧报告里的“当前”“下一步”不产生任务。
