# 性能开发与短验证

2026-11-11起，旧GitHub CI、260组回归、12片执行/聚合与每包自动模型审查退役。没有完整check、CI绿色或完整迁移验证的提交门禁；不再维护旧测试的兼容入口。旧代码与证据通过Git历史按需查找。

## 开发循环

1. 从普通Demo的实际性能选最大成本，说明这轮要减少什么工作。
2. 改数据、算法或执行架构；允许删除旧实现，不为保旧测试绕路。
3. 用相同人数、命令和采样时长比较实际世界流速、帧时及主线程成本。有新失败或结果不明时才追加针对性检查。

默认性能对照为20–30秒样本，冷启动和预热另计；没有可信整体收益就重选方案。大型负载、长局和GPU专项按当前问题临时运行，不自动变成每次开发的回归。

## 保留的短检查

`python tools/godot.py test`仅运行三个最小smoke：结算顺序/预算续算、CPU批数值一致、库存转移守恒。没有完整Main、全内容库、长时间世界推进或历史迁移装配。默认进程上限15秒，发生错误立即停止；超时就缩小或修复该检查，不能不断放宽。

可以用`--suite settlement`、`--suite actor_batch`或`--suite inventory`只选受影响部分，`--list-suites`列出范围。新检出或新增class需要时单独`import`，不在每次test前重复导入。工具只保留一项运行器退出/超时smoke，不恢复旧Python工具全套。

文档修改看差异和必要链接；场景修改实际打开相关场景；存读或规则修改只验证本次会破坏的具体路径。短检查不证明游戏全部正确。只有可重复且实际昂贵的故障才值得增加永久检查，不规定测试数量或要求每包新增用例。

## 性能入口

```powershell
python tools/stress_demo.py --residents 150 --seconds 20 --quit-after-capture
python tools/diagnose_demo.py --seconds 30 --auto-start --quit-after-capture
```

前者两地合计300人，后者观察普通开局；JSON/JSONL在logs。headless只用于CPU或工具诊断，画面性能用真实渲染器。报告保留实际代码与负载，不把worker活动或独立GPU kernel提速当成普通游戏加速。

手动review可按具体风险使用，不是每包必跑。不查询旧CI，不因提交、推送或小修改自动开额外回归。短验证由同一进程等待，模型不定时读日志或报百分比。现状记[HANDOFF](../../status/handoff.md)，有效性能证据记[BASELINE](../../status/baseline.md)。
