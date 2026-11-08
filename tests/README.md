# 验证入口

本页只说明如何找到测试；验收结果及准确SHA见[BASELINE](../docs/status/baseline.md)，运行特性见[FEATURES](../docs/status/features.md)，真实旧档及只读要求见[fixtures记录](fixtures/README.md)。历史测试目录详述保存在[整理前快照](../docs/archive/documentation_consolidation_20261104/tests/README.md)。

- sim/：纯规则、对象/资源所有权、冲突、知识、环境、共同时间及批算。
- runtime/：实际场景/行程、地形、输入、联合存读和迁移；runtime/helpers/为测试重放助手，不代替产品过程。
- fixtures/：不可改写的真实历史档和来源记录；新格式不能靠覆盖旧档凑通过。

真实历史来源不可改写，不等于永久支持全部旧版。当前测试覆盖与运行支持范围按[兼容及退役政策](../docs/engineering/compatibility.md)调整；有价值的场景建立当前格式回归，退役后历史解释器及其主CI路径可移除。测试成本优化使用最小合法装配，历史fixture保留原字节。
- 根目录test_*.py：工具链和CI观察器的Python测试。
- tools/qa/：相关行为的定向探针；按具体系统和QA记录选择。

tests/run_tests.gd同步执行注册的test_*，输出断言并非零退出失败；它不自动等待coroutine。若需要跨帧/`signal`验证，先确保runner明确等待、超时且失败传到退出码。测试必须核可观察的规则/归属/失败行为，而不是只验证没有报错。

~~~powershell
python tools/check_structure.py
python -X utf8 -m unittest discover -s tests -p "test_*.py" -v
python tools/godot.py test --list-suites
python tools/godot.py test --suite test_environment_field_cache --test-timeout 120
python tools/godot.py test --list-suites --shard 1/12
python tools/godot.py test --test-timeout 1800
python tools/godot.py check --test-timeout 1800
~~~

check包含结构检查、导入和完整GDScript回归；按改动先选相关定向验证，同一代码包的完整回归可由对应SHA的GitHub CI承担，无须每个文件重复全套。纯文档只查结构/链接和差异。存读改动还应覆盖迁移、进行中恢复、失败不污染活世界及适用的完整停开；涉及画面须实际运行、查看截图和日志，性能须记录实际规模与测量，均不能由无头绿灯代替。

`test --suite`接受重复的完整注册名称；未知名称失败，选组通过只证明这些组。`check`不接受`--suite`。`test`/`check --shard INDEX/TOTAL`仅执行完整注册表的一片，不能和`--suite`混用；单片成功明确标为部分覆盖。CI用12个独立worker执行，各worker门禁成功后再用`python tools/check_test_reports.py logs/ci-shards --shards 12`确认相同注册表的每组恰好执行一次。本机分片运行保持引擎串行，聚合报告之外仍须检查每片退出码。

测试默认输出逐组耗时/断言增量及最慢十组，并把开始/完成记录逐组flush到`logs/*-timings-*.jsonl`；可指定`--timing-report PATH`。超时后一次读报告定位，不轮询。永久测试准入、最小fixture及CPU/GPU分工见[测试策略](../docs/engineering/workflow/testing.md)。

结构检查不核外部网页、历史archive、动态拼接路径或标题锚点；.tscn/资源UID及画面仍须按对应技能和引擎验证。生成日志/临时截图使用忽略目录，QA里程碑按实际证据记录，不把不存在的日志当通过。

静止来源实际响应的开发验收：`tools/verify_environment_response.gd`用真实渲染器及第二次`-- --read`检验完整停开；`python tools/bench_environment_response.py --size 64 --events 32 --snapshot`测原物/材料背景、CPU候选/响应与存读。只在显式声明的封闭区域/会话内有效，不是普通Main新环境。性能基准与完整check按主代理统一顺序运行，不并发两套引擎回归。详见[响应QA](../docs/qa/20261105_environment_response.md)。
