# 读档首屏：视口优先、暂停绘制与原事实连续

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

2026-11-04；Godot 4.7.2，Windows / D3D12 Forward+，1280×720、相机缩放1。分支`codex/world-view-continuity`；规格见[首屏呈现](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/world_view_continuity.md)。本机定向和原生验收已进行，最终完整回归须对应本包提交，不能借前包绿色代替。

## 原问题与实际变更

私人交割旧截图每次先重新读档，再立即截图。独立候选地图接回后会清空旧瓦片；原地形扫描按区块行序每帧256格，真实档玩家在(256,228)，其区块内行序偏移2304，尚未绘到就会拍到黑背景。原生等候两秒后，地形、迷雾与人物均恢复，读得的相机位置也正确。因此本包修复首屏的绘制顺序，不把这个证据外推为所有历史显示异常的唯一原因。

`main`根据实际相机、视口和缩放提交地格范围；`ReolWorld`优先画屏幕中心、包括相邻区块，剩余预算继续原扫描。总地格写入仍每帧最多256，未完成的区块不得提前记为loaded。地面、植被和崖面共用原地图投影；部分崖面仅含已绘格，普通扫描后交回完整区块。重绑、远跳与工具取消均有清理/重新排队，不能遗留离序预绘格或让相同视口永久不恢复。

不改模拟、地图生成、存档格式、感知或全局渲染设置。`is_view_ready`只认世界内请求格均已写入；超过当前加载范围仍返回false，不代表授予可见性或GPU已经呈现。相机保留原自由平移与F居中，行旅没有被强制改为跟随。

## 本机验证

`logs/world_view_focused.gd`统一执行自然视图、世界呈现、器物视图与真实私人交割连续性四个套件；最终日志`logs/world-view-focused-final.log`为266断言/0失败，退出0、无SCRIPT ERROR/ERROR。断言包括：跨区块475格两批就绪、中心优先、重复请求、正常扫描无漏、边界裁剪、超加载范围不就绪、崖面mask、取消/远跳/重绑、会话和共同时间不变。无本地重复完整check，完整回归交具体提交的原CI。

真实源为未改写的[session_v42_exchange.json](../../../tests/fixtures/session_v42_exchange.json)，SHA256 `e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf`。首次原生探针读档返回0，暂停保持551887ms，相机(16416,14624)，玩家(256,228)，21×14格首屏：第一次process_frame观察尚0格，随后两批为256/512格，第三次观察ready；从开始等待到就绪113246μs。完整会话JSON在绘制前后相等。这里记录的是端到端等待，不能换算成单帧CPU耗时。

原生同一进程连续重载真实档的三条分支均`load=0`、候选有效、暂停和完整快照相等，约三次process_frame观察后ready；实际画面已查看：

| 入口 | 时间与事实 | 图 |
|---|---|---|
| 正常新局选本人 | 0ms，原山门人物/场所/地形显示，候选有效 | [新局](20261104_world_view_opening.png) |
| 暂停读档、收起交互 | 551887ms，原交割进行中，地形/人物/迷雾接续 | [首屏](20261104_world_view_paused_load.png) |
| 重载后交割进行中 | 原6钱、原预约未完成，面板和背景均显示 | [进行中](20261104_world_view_pending.png) |
| 重载后推进余下3秒 | 554887ms，原钱包变2钱，原环交付 | [完成](20261104_world_view_completed.png) |
| 再次重载后本人停手 | 551887ms，原6钱，预约释放，无钱环转移 | [取消](20261104_world_view_cancelled.png) |
| 正常行旅到河湾并F居中 | 用原路线/原身体，已到河湾、候选有效，居中与绘制不改事实 | [行旅](20261104_world_view_travel.png) |

原生脚本/返回值在`logs/world_view_{opening,audit,exchange,travel,benchmark}.json.result.json`。重现只调用真实loader/原产品命令和共同时间；绘制采样临时停用自动process，再手动调用相同呈现函数，不修改钱、意愿、位置或地图规则。渲染后再截图，不用进程累计frames_drawn冒充本次重载已等待帧数。早期行旅探针误用了只认断碑台终点的helper，返回arrived=false；之后按实际行程为空且current_region=river判断，旧结果不算已到达证据。

末版run11首屏CPU采样（调试进程、冷的新候选地图）中，四批绘图分别7914/7283/7354/7462μs，视口准备首批1133μs、后续30/28/31μs；每批新增256格，第二批就绪。这不包括GPU、崖面_draw及整帧UI，也不证明8K、远跳删除、全世界或发行性能达标。排序、卸载和崖面仍有额外工作，不宣称256格限制了整帧总CPU耗时。

## 错误和范围

早期临时eval误用了自身不存在的`get_viewport_rect()`，导致脚本编译中断；改为`main.get_viewport_rect()`并停止/重新正常启动后复验。此处不是产品脚本失败，保留原日志。

后续run9确有产品视图错误：重载后旧器物域的弱世界引用在`can_see`与`object_cell`之间失效，`SimArtifacts.valid_location`访问null。官方4.7.2的GDScript VM在行边界进行debugger `line_poll`，累计2048次后可处理消息；Godot AI的捕获会立即执行eval，因而重载可以重入同步绘图。不能假定两行之间永不替换会话。源码依据：[gdscript_vm.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/gdscript/gdscript_vm.cpp#L3656)、[engine_debugger.h](https://github.com/godotengine/godot/blob/4.7.2-stable/core/debugger/engine_debugger.h#L117)、[remote_debugger.cpp](https://github.com/godotengine/godot/blob/4.7.2-stable/core/debugger/remote_debugger.cpp#L604)。未改第三方插件。

器物视图改为在一次观察/绘图内保有同一已接受世界的强引用，并向可见性/绘点传递它；原域继续弱引用所有者，不新增模拟状态或吞掉错误。确定性回归在可见性查询内替换会话，要求旧世界活到本次读取结束、之后正常释放，新世界保持原事实。另两组原生12次stage释放/12次重载与大量查询均owner匹配、引用数稳定；它们帮助排除普通候选串用，但单独不能证明间歇错误已修。最后以确定性回归及末版原生重载路径为准。失败运行与其截图不作末版干净证据。

末版当前游戏日志仅helper启动行，无错误/警告；编辑器仍有既有整数除法/命名等警告，未宣称整个项目零警告。

本包没有正式美术、全动作/脚步音、整个自由镜头范围生成、海量区块性能或原生音效验收。完整游戏和首小时切片仍未完成；下一玩法由实际计划继续。
