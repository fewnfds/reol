# 短检查

旧260组测试及其Python工具回归已退役，旧实现保存在Git历史。当前不运行CI或完整回归。

```powershell
python tools/godot.py test
python tools/godot.py test --suite actor_batch
python tools/godot.py test --list-suites
python tests/tool_smoke.py
```

`smoke.gd`显式选择三个最小检查：结算顺序和续算、CPU批一致、库存守恒。默认测试进程上限15秒，不导入全世界、不推进数小时、不扫描全库或旧档。新检出先按需`python tools/godot.py import`。

`tool_smoke.py`仅检查包装器的正常退出、首错停止和超时，通常数秒完成。两者都不代表规模性能；性能开发使用[普通Demo测量](../docs/engineering/workflow/testing.md)。历史fixture原字节保留在[fixtures](fixtures/README.md)，不自动执行迁移回归。
