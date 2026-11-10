# E3-a：野药、有限水与真实照料验收

2026-11-03。**有限包已实现，七组定向、真实进行中完整停开与最终完整check已验。** 最新构建数字只见[BASELINE](../status/baseline.md)，实现规则与覆盖边界见[规格](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/herb_ecology.md)。完整生态、E3地形改造、P1–P4和45–60分钟切片尚未验收。

## 实际接通与状态归属

两地原`herb_slope`在原cell/来源身份上拥有有限土水、温度/雨况缓存和生长/休眠进度；成熟药草仍只在原`resource:herb_slope`库存，真正采集、原预约/私有与受托责任不变。原固定两小时免费增长停止，其他来源保原规则；来源库存满不积累无限待领产量。植物不是新增人物平台，也不是可选植物人生。

原`SimLandResources`拥有生态状态，纯`SimHerbEcologyRules`按实际整数水量/生长工作积分，保存吸收、蒸散、降雨、灌入、溢流和进度依据；不从查询次数或浮点舍入生成药草。父级每分钟先用旧缓存结原来源，再读真实地理气候/天气/已支持的同格余热作为未来条件。干湿滞回避免微雨导致毫秒开关；冷/干时保进度，成熟药不腐坏。雨水不是水行灵气，也不是把原泉源收雨再领一份。

玩家从原“生活与办事→采集”页执行`irrigate_herb`：本人真实可处分水预约→原身体/路线→到场两分钟劳动→完成一次耗一份原私水并入土。候选先核全部影响再无yield共同提交，原`action_id:irrigate`consume与`irrigation_receipts[action_id]`双向核对；取消/控制丢失/预约失效不先灌入，原公物不能借入口私用，已耗工时不退。照料零贡献，界面不说去功德堂领功。

附近当前可见且满足原观察距离才读药丛阶段/土面干湿线索；有成熟药时仍能看见干冷。远处不公开实时土水、温窗或成熟倒计时，不依据远程土水禁用按钮。两地garden使用只读代码像素药丛，视图卸载不删除来源、绘图不推进生长。

本包格式为根33/区域29/村落6/来源3，生态规则和状态1。真实v1–v32只读迁移；旧来源以原保存时刻启用36000000微量初始土水并登记当前未来条件，历史已产/已采/库存/人物在途、衣着/雨水/温石和余热保留，不追补过去生长。真正没有来源的早期世界不补药源。完整候选成功才提交，JSON绑定时将已校验生态整数规范化，避免多次往返污染大整数/时间上限。

## 自动验证

以下为本包最后收到的定向命令输出，均0失败；不把各组断言相加当成功能数量。完整check最终数字仍由BASELINE维护。

| 入口/日志 | 断言 | 主要覆盖 |
|---|---:|---|
| `logs/herb_ecology_rules_probe.gd` / `logs/herb-ecology-rules-probe-20261103-193830.log` | 155 | 单一有限源、干湿/冷暖/旧缓存、整数水量/吸收工作守恒、真实私水、显式旧基准、重复JSON |
| `logs/herb_irrigation_probe.gd` / `logs/herb_irrigation_probe.log` | 158 | 原路线/两分钟劳动/私水预约、取消/控制/责任、公私混合、劳动中雨/溢流、进行中候选和严格拒绝 |
| `logs/herb_ecology_runtime_probe.gd` / `logs/herb-ecology-runtime-20261103.log` | 41 | 原采集页实际汲泉后照料、取消不扣/完成只扣一次、零功、附近/fog/距离和身体控制 |
| `logs/herb_ecology_limits_probe.gd` / `logs/herb-ecology-limits-probe-20261103-194013.log` | 84 | 首个满一分钟、末尾合法采样/非整分上限、持段雨量、来源精确JSON；轻量边界fixture不等于多年满人口性能 |
| `logs/herb_migration_probe.gd` / `logs/herb_migration_probe.log` | 415 | 只读v1–v32、原v32各域不改、现代缺域/伪造水/温雨/来源/孤立consume与原子拒绝 |
| `logs/herb_environment_probe.gd` / `logs/herb_environment_probe.log` | 48 | 实际地理分钟采样、干/冷/真实雨恢复、近远/预算同未来、持段雨预算、原私采/焙药/取回 |
| `logs/herb_archive_probe.gd` / `logs/herb_archive_probe.log` | 22 | 真实v33、两个独立主场景、一次原水→采药→焙药/取回→离场、完整候选与同一未来 |

另有`logs/herb_canvas_draw_probe.gd`真实CanvasItem绘制通知4断言/0失败，`logs/herb-canvas-draw-20261103.log`核只读阶段和原土水/库存不变。该无头探针不代替下面实际截图。

## 失败、修正与最终回归

首次迁移定向在70001ms拒绝本应合法的联合候选。只读探针发现stage只把新村落候选时钟移到70001ms，生态仍留0ms，区域初始化报`Invalid opening plant environment`，尚未到真实restore。修正保持独立候选的真正开局时间，再由完整恢复提供保存时刻；`logs/herb-stage-trace-70001-20261103.log`与`herb-stage-zero-baseline-20261103.log`保留定位证据。临时绘图/定位脚本曾在autoload注册前静态加载GameClock依赖而失败，改为启动后动态加载；失败日志仍保留，不涉及生产规则绕过。

JSON和时间极限审查补了已校验整数规范化、最后合法整分/不足整分不造采样的反例。来源和土水守恒不因修复放宽，参见规则155及limits84输出；长时轻量边界fixture明确排除完整人口/路线成本。

首完整check的`logs/check-test-20261103-193503.log`暴露原懒同步断言与E3逐分钟受管植物同步冲突，也有旧schema/严格迁移fixture问题，检查被中断，不能写成完成通过。后续`logs/check-test-20261103-193901.log`仍失败（该次113 passed/33 failed），保留错误和级联日志，不作为当前绿色证据。修正中的历史合成fixture只移除其声称不存在的新字段，真实历史档未改；原性能测试显式采用无受管植物fixture，保留真实懒远区、快照同步和73分钟同未来断言。该套`logs/demo-lazy-region-20261103.log`90断言/0失败，其余普通场景仍有生态，不通过关闭正式生态伪造性能结论。

随后修正真实非零时刻新场景初始化：原村落/来源在同一opening_ms建立，而非初始化后只改村落时间。世界持久化与有限信息原组定向235断言/0失败，合成pre-health旧格式110断言/0失败，旧热场/区域稀疏依赖189断言/0失败。最终`python -u tools/godot.py check`在`logs/check-test-20261103-194721.log`和`check-import-20261103-194715.log`完成，退出0、CHECK PASSED，无ERROR/WARNING/FAIL；当前总数只维护在BASELINE。原生视觉命令退出0，资源引用严格检查0错误/0警告，15项Python工具测试通过；其中故意错误日志是失败检测测试的输入。代码像素九PNG/manifest确定性重建通过，未以新增资源取代玩法。

测试曾preload被.gdignore排除的tools/qa目录而触发一条严格引用警告；重放实现现放在受扫描的`tests/runtime/helpers/herb_ecology_replay.gd`，原QA入口继承同一实现，档案定向22断言/0失败。源码/未来未变，引用警告已消除。

最终完整check已通过，日志`logs/check-test-20261103-194721.log`，当前数字只见BASELINE。旧D3D12间歇呈现、WASAPI声音和正式动画/规模问题不因本包通过而算已修复。

## 实机操作、真实档与完整停开

run172通过鼠标选择人身，在原采集页启用自留采集，实际汲泉得到本人私水，再点“浇灌野药”，用原保存器在劳动中途记下新v33。没有注水、瞬移、改NPC自主或覆盖旧fixture/普通用户档。

- 源档[session_v33.json](../../tests/fixtures/session_v33.json)：189595字节，SHA256 `d1a4e0f5fbaa4b87728f34723fe75876647ccd114f3622ef830fd17f7822c9e2`。
- 保存时刻1333120ms，原`action:11`为`irrigate_herb`、phase为work、目的garden，`action:11:water`仍预约本人水；行动开始1300450ms、到场劳动开始1303120ms、应完成1423120ms。行囊水12、钱6，`irrigated=0`，尚未提前耗水或灌入。
- run173/run174分别完整停止并重开游戏，均由原loader读同一源档，再执行[重启探针](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/tools/qa/herb_ecology_restart.gd)。两次在1423120ms完成后均水11、仅一份60000000微量灌入与一个来源回执。随后修正非零时刻新建场景的初始化接缝后，再以最终代码完整停开run175/run176，完整未来仍为相同172612字节及下述SHA。
- 随后原私采药得到2鲜药，原私拾柴得到3木，原私料焙药实际消耗2鲜药及1木，再实际取回2干药。之后通过原路线前往河湾，推进到相同7200000ms，行囊为水11、干药2、鲜药0、木2、钱6；这条实机证据没有卖药或诊治。
- 原药源此时`extracted=2`、`produced=1`，土水输入包含真实降雨42000000与本次灌入60000000，保有102000000微量水；植物仍归原空间，离场不重置。两个未来均`candidate_valid=true`。
- 完整联合未来两份各172612 UTF-8字节，SHA256均为`8eacf7a6f251e0cf6e09c2804ce3c6299fb7a886758904d35e0d5e3743fd020f`；`logs/herb_ecology_future_a.json`/`_b.json`及`logs/herb_ecology_restart_a.json`/`_b.json`保留原输出，逐字节一致。

已查看`logs/herb_ecology_irrigation_inflight.png`：嵌入窗口为853×480像素，使用1280×720逻辑UI缩放。随后执行`Godot --path . --resolution 1280x720 --script res://tools/qa/herb_visual_capture.gd`，原场景/原loader载同档，保存并查看**原生1280×720**的`logs/herb_ecology_native_1280.png`；命令日志`logs/herb_ecology_native_visual.log`，退出0、图片保存0。采集页、随身水12、浇药工时与像素人物/药丛可见，长描述受三行限制、全文在tooltip。该视觉探针只读原存档和设置显示页，不注物资/位置。未验全部分辨率/方向美术，证据只证明当前有限包。

## 限制与下一步

仅两处固定药丛、一个生长模型和原cell身份；有界土水/大整数不是全物理水循环。父级每分钟同步受管地区，近远同规则但多年满人口/海量植株性能未验。当前热场仍有原512激活格且不回收等限制，不因植物接入解除。

采集成熟药不伤根、成熟产物不腐坏、植株不死；没有播种/留种/繁殖、土地权利、公共照料授权、NPC自主农务/长期规划、地形delta/水利/温室、植物自我扮演、五行/风水。原place格仍受施工保护，不能声称已能给药丛直接盖棚。继续把既有生活/创造/修行与冲突逐包接成可玩链，当前不是完整农业、医疗、市场或大世界游戏。
