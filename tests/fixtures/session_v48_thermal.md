# 热 v2 的真实旧代码存档

2026-11-05，以旧提交 `c6061d56326a10b98dd04b75e98ba9344bba6ea6` 的独立 checkout、Godot `4.7.2.stable.official.ed1daf0bf` 生成。两个文件均保留普通旧保存器写出的原字节，不由当前格式倒写版本号。

源为不可改写的 [session_v32.json](session_v32.json)，SHA256 `a804cc0707f0e1be89372868bbdb58dc4544b4b1aa4e296a00dd999c185cd88a`。旧代码通过普通 loader 在 `797431ms` 接续其中真实进行中的 `warm`，共同时间实际推进至 `840050ms` 完成原动作，扣原温石储量并留下 `artifact:action:11` 的 `180000000 Q` 来源回执；未注入余额、学习、位置或新器物。

| 文件 | 保存时刻 | 原格式（根/区域/热/器物） | 字节数 | SHA256 |
| --- | ---: | --- | ---: | --- |
| [session_v48_thermal.json](session_v48_thermal.json) | `905173ms` | `48/40/2/7` | `273182` | `216999c8399e8fff4c345bf8ad5dd375fa58c19cc66bae4510f43b47df1715d3` |
| [session_v48_thermal_future.json](session_v48_thermal_future.json) | `957520ms` | `48/40/2/7` | `273229` | `51f8dd3824f3e411ac4d95504d3b62963a5f3bbb9ea884a333eaeea44a363419` |

首档含 25 个实际分配格，冻结段始于 `900000ms`，保存落在段内，历史绝对 Q 样本也在 `900000ms`；原模型起点和空旧格式证据仍为 `797431ms`。伴档由同一旧进程不间断再推进 `52347ms` 后普通保存，冻结段始于 `950000ms`，历史样本仍为 `900000ms`。

干净生成记录为 `logs/device-v2-generate-clean.json`，当前普通导入与完整同未来验证为 `logs/device-v2-verify-final.json`，均无引擎错误；后者规范化完整未来 SHA256 为 `6a5166a35cda63b58c0c4bbe8a32519ed96bc173266b0978078d0daec0c915ec`。首次带纹理缓存错误的生成记录不作为证据，干净生成的两个存档字节与其相同。

回归入口为 [test_thermal_device_migration.gd](../runtime/test_thermal_device_migration.gd)。测试只读这两个旧档，升级到当前唯一格式后比较原字段、普通 load、完整未来及损坏候选原子拒绝；不得用测试重新生成或改写本档。
