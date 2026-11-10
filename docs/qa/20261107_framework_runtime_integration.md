# 通用实物普通接入

## 范围与边界

在既有普通主场景和普通存档内补通定义实物的生成/移除、取放与取消，不新增演示世界。采用Godot4.7.2；原四份环境WIP保持独立，不纳入验证。计划和环境未接入原因见[接入范围](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/plans/world-foundation/runtime-integration.md)。

- F8开发编辑按当前physical定义生成/移除，支持真实多格。开发生成不扣材料，不能冒充普通玩家制造权限。
- 既有物品面板使用原生命周期耗时取放，启动/截止同高触及及遮挡复验，原行动占用、取消和普通联合存档不另造副本。
- 新冷热/五行/GPU、通用材料菜单、携源轨迹、完整产权与NPC指挥均未接入。本包不继续密度压测或专用存档优化。

## 实际证据

干净隔离检出只复制本包6个代码/测试文件，未复制四份WIP。导入成功；定向4组457断言0失败：`test_world_objects_runtime`、`test_terrain_edits`、`test_object_actions`、`test_object_lifecycle_continuity`。新增普通主场景链覆盖编辑生成/多格移除、远距与他人持有拒绝、取消、进行中存读、截止前1ms、取放、多格占用与途中接触阻断。既有组复用，不另建整套验收框架。

首次新增链使用旧FlatMap测试夹具，被编辑器的平面描述校验拒绝；改用真实main和实际地图后通过，没有放宽编辑守卫。初次临时实机脚本过早静态加载依赖GameClock的运行类，编译失败；改为场景装配后动态取接口。两次失败仅验收夹具，日志保留。

真实渲染器D3D12/Forward+/RTX3060、1600×900：普通Main以`--world-editor`启动，原F8键打开编辑，真实鼠标点击放置2×1长石板；退出后既有面板取起，517ms普通存档。完全退出后第二进程由普通加载器恢复，同一完整世界快照摘要一致；原动作在60000ms完成，普通面板再放下并在120000ms完成，同一身份落回原地面。write/read均0失败，未出现ERROR/SCRIPT ERROR。

证据保全位置：`logs/framework_integration/`（忽略产物）。`dev/logs/targeted-final.log`、`visual-write.log`、`visual-read.log`及`object_editor.png`、`object_pending.png`、`object_restored.png`；收尾时保全到`validation-artifacts/`。临时脚本只为本次真实画面/停开证据，不新增产品路径。Godot AI当时无连接会话，使用原生引擎启动和viewport截图，未修插件或调用裸HTTP。

## 完整回归与审查

首代码`f7baba0279fccb8d4592dc30194ddaa50dbf7f12`。一次原生Sol/custom静态审查发现P1：暂停未完成T等待后启动取放会保留wait目标，普通保存成功但候选加载因两者争用wait范围而拒绝。已窄修为成功schedule后取消旧wait、取放占用期间拒绝新wait；非法点击不取消原等待。最终4组469断言0失败，原链覆盖两种顺序及进行中普通存读。没有启动第二个整包模型审查。

首轮完整check在收到此真实P1后由主代理核对并终止自己启动的引擎，结果是主动中断、不是通过或产品测试失败；其代码与首SHA的6份文件指纹一致，但隔离HEAD当时仍207a0cd。随后清理仅属本包的隔离修改、切到最终修复`f641ddd035a588b504574df32617d708507cbd71`的干净HEAD运行check。结构与导入通过，**完整回归因用户要求暂停而主动中止，仍待验**；不提高1800s上限、不冒称通过，不自动重启。日志和实机证据保全后移除临时检出。

提交检查点顺带核对前包：A `9467cb9790229284ee24edd61cc48a45d809d1f0` 的CI42269548713 completed/success；B `603cdff7a65672e486b831453ec9114a71ea1ade` 的CI42270554012因完整Godot回归1800s超时失败，日志停在world_persistence，无最终汇总，不能称通过。Python日志中的故意失败样例不是该超时根因。未改门禁、取消run或轮询。
