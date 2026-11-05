# 验证基线历史分卷 12

> 历史记录：下文的版本、权限、下一步和 CI 状态只描述记录时，不代表现状。当前证据见[基线](../../status/baseline.md)。

### W2b-1 固有微光、承载位置与有界查询

2026-11-05，原SimArtifacts新增intrinsic_light能力及严格原lighting v1，普通新局home/river住处各发行一个原珠子/薄片。固有光只作相对照明，不发行热量/qi/第二物品或余额；可以与weapon/remote_draw合在同一个实例，能力顺序无关、原动作协议保持。两个主动工具或热出流/固有光争用同一lighting语义严格拒绝。原火石仍按真实有限热流发光、关闭仍保余热，未接移动热。派生只读排序ID索引在创建/字段生成/恢复后重建，归处变化沿原位置查询，不存移动坐标。动锚点旧时刻或欠算unknown；固定地点/野外槽允许懒结算记录钟，不由查询推进世界。无新根50/器物8/37文档格式或历史解释器。

doctor正常；最终导入5.825秒/1006456832B、无引擎错误（`logs/intrinsic-light-import-final.json`）。新规则/真实Main/原有限热光/普通视图四组854项0失败，13.675秒/405794816B（`intrinsic-light-final-targets-grouped.json`）；最终动锚点守卫/组合/分组249项0失败，2.561秒/236412928B（`intrinsic-light-final-owner-gate.json`）。覆盖两种独立完整定义、同物武器能力组合、真实取放/连续路径、读回索引不可改/不入档、128源及128+真实热源拒绝、实际建门/开关/拆除、81格逐源取整和复用一致、欠算/旧位置与查询不改世界。默认Main普通取放/行走、进行中take独立恢复完整同未来、当前视野/魂体边界和真实旧49无新物/光已验；原fixture保持原字节。

原引物精确时刻/占用/几何变化两部分101项0失败，10.404秒/229908480B（`intrinsic-drawing-parts.json`）；一次合组及一次完整引物组各触发30秒上限，保留timeout，不称完整引物通过，完整回归留对应SHA CI。旧式健康源测试改为只在零时刻核空热账、精确开局行及全引用后排除历史定义不存在的后来开局物，并重建派生索引；真实旧档不改，相关旧源54项0失败，3.370秒/416129024B（`intrinsic-health-legacy.json`）。没有删断言或放宽产品加载门禁。

有界[查询基准](../../../tests/benchmarks/intrinsic_light.gd)，i5-13600KF/20逻辑核、Godot4.7.2 headless开发程序；原器物分别真实发行，同格源含两种峰值/半径，441受光格、30样本。先测得128源逐源查询p95/p99=34.844/36.194ms，热点为相同贡献重复计算。当前只在单次查询按格/半径/峰值共用**各源已经取整后的**贡献，再乘源数，不先合峰值，源预算仍按真实引用数核验；无持久空间/光缓存：

| 固有源数 | mean / p95 / p99 | 完整进程 / 工作集峰值 |
|---|---|---|
| 1 | 0.4803 / 0.636 / 0.716ms | 2.248秒 / 226889728B |
| 16 | 0.8620 / 1.019 / 1.148ms | 2.351秒 / 226439168B |
| 128 | 2.7564 / 2.915 / 2.925ms | 2.353秒 / 226287616B |

日志`intrinsic-benchmark-{1,16}-final.json`、`intrinsic-benchmark-128-grouped.json`，改前`intrinsic-benchmark-{1,16,128}.json`。这是同格的即时查询负载，非128个分散移动源、FPS、多年或热格容量。首次一源末测误与仍在运行的分组回归有短时重叠，未用于上表；终态后另行顺序重测。所有进程仍有30秒/1GiB外部限制，未并发整套回归。

[原生脚本](../../../tools/qa/intrinsic_light_capture.gd)在入树前选经度180°的新局，在民用08点实际夜间，真实到住处/取物/走六格/返回放置。1600×900的placed/held/moved/returned/restarted_held图逐张观察，最终用普通相机跟随且收起检查窗，让真实光与承载人可见；路径`logs/intrinsic_native_<label>.png`。每次等绘制完成后逐像素核GPU纹理等于实际提交图，当前视野外全黑；不凭headless判断GPU。write/read分别7.429/6.127秒，工作集605958144/597352448B、采样私有峰934002688/936632320B，D3D12 Forward+/RTX3060，0引擎错误。报告/guard为`intrinsic_native_{write,read}.json`和`intrinsic-native-{write,read}-final.json`。

保存的是进行中take，checkpoint SHA256=`991185503e5971aface2fb9ebbfc85e677a0a7c8c26c63c99e38f171c44c44fa`；完全退出后新进程加载，再31234ms完整未来与原进程均=`4e18f915d799d6529d8b2911a6de05a2f260076ed97f0f1efcc7b37830f05194`。W1b既有原生50另由普通loader读取，原checkpoint/12347ms未来摘要仍通过，未补珠子/薄片（6.074秒/589832192B，`intrinsic-old50-native.json`）。

初期无头纹理读回7条假失败定位为dummy渲染的ImageTexture.update读回仍为初图，force_sync不修正；保留失败日志。runtime保留本次实际上传图供无头断言，原生QA等待frame_post_draw再独立核GPU，未只删掉视野检查。首次把关闭一个火石等同整幅灯灭的旧测试也已改核原热出流确已消失、其他来源继续作用。API依据目标4.7官方[RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html)、[视口绘制完成](https://docs.godotengine.org/en/4.7/tutorials/rendering/viewports.html)，参考同步不进入每帧产品热路径。

本包提交检查：前推送12f4cf9/run41913715806 completed/success，artifact `logs/ci/41913715806-artifacts/`中227组/29794断言/0失败且无脚本错误，更新为当前前序完整绿色；W1b最终99eb91c/run41916383335仅一次发现仍in_progress，留下一真实提交，不等待/轮询。本包原生审查和最终SHA完整CI接续，Goal仍active。子代理曾越过文件/验证分工并误建自身Goal，已中断该代理；其未协调探针不计最终验收，主代理接管后重验上述原生/定向，AGENTS已加仅主代理管理Goal和显式验证分工，主线程Goal未重建/缩小。

W2b-1代码`542cb9820ec52a6b96b235550e5d023dc341f094`的一次Sol/custom显式read-only原生静态审查132.798秒、退出0，无可操作发现；核能力组合/严格定义、派生索引生命周期、原保管/已接受位置时钟、整数光贡献复用、Fog/CPU与GPU验证、候选恢复及旧版保留。未运行引擎/测试/基准/CI或修改文件，不重复整包审查；日志`logs/reviews/<SHA>.explicit-sol.log`及`.explicit-sol.summary.json`。26文件暂存检查无凭据模式、第三方/原fixture/生成输出及超大资源；结构201当前文档/398脚本0错误，diff通过。代码与此登记文档阶段推送，推后不查询/等待CI，最终SHA完整回归仍待验，Goal继续active。
