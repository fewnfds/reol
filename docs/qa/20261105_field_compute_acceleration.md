# F1：有界缓存与桌面GPU计算

日期：2026-11-05。沿[源场合同](../plans/world_environment.md)实现；F1是隔离计算基础，**尚未替换普通Main的旧热运行模型**。当前没有一个能提高Main性能的玩家设置按钮；下文auto/cpu/gpu是已验计算服务接口，待F2接入同一世界环境域后才能作为玩家设置。

## 当前实现与所有权

- `SimEnvironmentFieldCache`：packed来源槽、每格链、按需16×16缓存；接收格逐通道按距离搜索，以历史最大源强和最大活跃半径核形成安全上界，已不可能超当前值就停。七通道max、圆形核和整数舍入与F0一致；不保存赢家ID，需要解释时可回查原索引。降低或删除来源只使上界偏高，不改正确性。旧/新范围分别失效，远移不使中间大片地面误失效。
- `EnvironmentFieldGPU`＋`assets/shaders/environment_field_compute.glsl`：Godot内置RenderingDevice，工作线程创建local device；源半径核在CPU预计算后上传，GPU用32位十进制分解准确计算最大约10^15的乘积舍入，不依赖GPU int64或浮点近似。分行dispatch并回读，不在游戏主线程sync；使用导入的RDShaderFile，以免导出包依赖原始GLSL文本。
- `EnvironmentFieldComputeRuntime`：同cache的auto/cpu/gpu策略。auto初值4096格是待调阈值；单次GPU区域≤512×512、快照≤64MiB，并有邻域×来源链密度工作预算。不支持设备、超预算、GPU错误或过期结果明确回退后续预算CPU工作，不把pending当零。取消只作废ticket，仍须poll回收线程，保留原待算工作；close不等待活线程。
- GPU只拿冻结投影，不读写原身体、物品、时钟或活cache。区域快照可只带最大半径halo，原global owner/revision/area负责发布；worker完整校验数值并拆块，主线程预检全组后原子发布。变更来源后旧结果拒绝，坏候选不部分改cache；返回数组与cache隔离。

只有一套规则与缓存，后端不是第二个世界或存档格式；当前尚无环境历史存读、原物到源的运行绑定或房间平均。CPU/GPU没有运行时LLM、新插件或第三方依赖。源数量不是Node数量。

## 正确性与失败路径

最终cache＋service定向35180断言0失败，2.361秒/222146560B工作集，`logs/field-service-compact-final.json`。涵盖小图F0全格、同位多个来源、最大等级、赢家删除/半径缩小/远移、私有块中途变更、pending预算、原子拒绝、跨owner/旧revision、局部halo/裁边/空窗口、结果准备和发布、取消及无设备回退。测试数不代表主游戏功能完成。

原生`tools/qa/environment_field_compute.gd`真实RTX3060/Forward+/D3D12，12案例全部通过，7636格/53452通道与F0对照；包含真实GPU、非方图/偏移裁边、移走最强、同物移动改半径、窗口外源、空窗口、过期结果拒绝后CPU最新值、取消回收、auto及重开。最终进程1.808秒、工作集410415104B/私有峰534491136B，`logs/field-gpu-native-service-final.json`。GPU完成必须报告实际硬件设备；没有用fake、软件设备或CPU回退冒充成功。

曾发现并修复真实原型错误：RD不存在的byte-limit枚举、PackedInt32Array转换/append返回值误判、RefCounted负号instance ID误拒绝。首错日志保留，不放宽断言凑绿。核表和单段响应纯规则审查相消P2已在9673e6b窄修，8130断言0失败，`field-response-reviewed-fix.json`；累计影响不是地块场前置。

## 性能证据与适用范围

统一外部owned-process守卫30秒/1GiB；Windows/i5-13600KF/20逻辑核/约32GiB，Godot4.7.2开发程序/RTX3060。密集基准一格一来源、七通道非零、半径4/8交错；初始装配与来源更新登记单列，不能算作免费。GPU完整端到端包含打包、**每job重新建device/pipeline**、传输/submit/sync/读回、worker准备、主线程发布及等待调度，不称GPU-only。GPU dispatch的p95/p99是单个dispatch等待，不是帧时。

CPU完整512²初建9686.711ms，1%分散变更使1024/1024块失效并重建9690.211ms，1024缓存点2.828ms；初建预算调用p95/p99=3.622/4.391ms，每次最多8192工作单元。`logs/field-cache-pruned-512.json`为前GPU接缝表示下的参照，非新增结构后逐周期CPU测量；工作集118706176B。首source-centric版初建20196.637ms且变后未完即30秒超时，保留失败不作通过。

| GPU场景 | 来源/实际输出 | 初次端到端 | 变后端到端 | 变更登记 | 主线程打包/发布（初次） | 进程工作集/私有峰 |
|---|---|---|---|---|---|---|
| 512²、1%分散改强度 | 262144源/整图 | 160.142ms | 166.335ms | 2621源/20.264ms | 4.505/1.957ms | 470044672/622297088B |
| 512²、10%改强度、中心128² | 262144源/16384格；halo20164源 | 85.121ms | 114.599ms | 26214源/173.245ms | 6.045/0.156ms | 365760512/490991616B |
| 512²、100%改强度 | 262144源/整图 | 159.727ms | 355.119ms | 262144源/1904.233ms | 4.317/2.193ms | 471506944/625786880B |
| 2048²、1%改强度、中心128² | 4194304源/16384格；halo20164源 | 221.589ms | 173.233ms | 41943源/284.183ms | 5.914/0.160ms | 576512000/715882496B |

对应`logs/field-gpu-change-{512-1-window0,512-10-window128,512-100-window0}.json`及`field-gpu-2048-window128.json`。512整图1%初次dispatch p95/p99=0.682/2.427ms，变后1.756/2.534ms。100%变后10.316/12.082ms；2048窗口初次14.159/14.159ms，变后5.969/5.969ms，有硬件/驱动调度波动，不能只挑最好值。32²高强度初变两次全格校验，较大图各24个分布格独立局部F0核对；不把采样说成全图逐格比对。

1024²全图1048576源也已通过24格抽检：`field-gpu-prepared-1024.json`总pack＋compute/prepare＋publish549.275ms，**旧口径不含95.515ms setup及close/调度**，主线程16.848/8.615ms；工作集598941696B/私有743251968B。正式可选service单请求仍限512，不将该独立基准当正式无界容量。

2048²全图一次性快照/传输在1GiB下buffer分配失败，`field-gpu-prepared-2048.json`，不称全图GPU通过。之后加入区域halo快照及明确64MiB快照/输入预算，才在同一4194304源地图通过128²窗口；**没有完成2048²整图缓存或真实世界实体验收**。初次4194304源装配19479.325ms也是实测成本，不能每帧重建来源。来源移动/遮挡/房间/长时及新模型存读仍待F2。

## 普通Main帧基线

`tools/qa/world_performance_probe.gd`真实普通新局选人身，无载档/写档/传送/伪造人口；等待地形流式清空及30帧稳定，再暂停/1x各180帧。1280×720/Forward+/D3D12/RTX3060，实际12人物、8器物、25已加载块、0活热格；1x自然共同时间推进1550ms，无积压/错误。帧间隔p50/p95/p99/max=8.332/13.473/24.764/31.491ms；暂停为8.334/8.372/8.414/8.621ms，帧率上限120、vsync关闭，317–321 canvas draws。进程13.580秒/工作集656596992B/私有986923008B，`logs/world-frame-probe-first.json`。

这是开局小规模、固定镜头、短时自然运行。Performance过程监视器刷新慢且可残留前段采样，重复75.594ms不是每帧耗时，结论以实际process_frame间隔为准。没有证明战斗/大群NPC或GPU与稠密世界同时运行时FPS达标。

## 采用结论与接续

GPU对密集max场有实测价值，保留为可选后端；小请求/无设备/大半径及超预算回CPU。查询缓存、时间推进、房间与业务事实保持共同规则。后续优先按地区/脏块请求，避免普通移动触发全图重建；可复用device/pipeline进一步降低setup成本，但当前未实现，不纳入加速承诺。

距离核已查表；微潮汐是常数次整数运算，暂无证据值得每格存长曲线。温度实际响应仍需先确定共同时间上的目标段与误差合同，不把“每帧实时微积分”当实现；可预计算共享响应曲线，但要核插值误差和整段/分段同未来。新F2接入前不在Main放一个无实际效果的GPU按钮。

官方依据：[Godot4.7 compute教程](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html)、[RenderingDevice](https://docs.godotengine.org/en/4.7/classes/class_renderingdevice.html)。Compute仅RenderingDevice的Forward+/Mobile；Compatibility不可用；传输与立即sync可抵消收益，dispatch须防驱动长任务。当前桌面优先，不将移动/Web作为前置限制。
