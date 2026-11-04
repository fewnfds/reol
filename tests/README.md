# 验证入口

本页只说明如何找到测试；验收结果及准确SHA见[BASELINE](../docs/BASELINE.md)，运行特性见[FEATURES](../docs/FEATURES.md)，真实旧档及只读要求见[fixtures记录](fixtures/README.md)。历史测试目录详述保存在[整理前快照](../docs/archive/documentation_consolidation_20261104/tests/README.md)。

- sim/：纯规则、对象/资源所有权、冲突、知识、环境、共同时间及批算。
- runtime/：实际场景/行程、地形、输入、联合存读和迁移；runtime/helpers/为测试重放助手，不代替产品过程。
- fixtures/：不可改写的真实历史档和来源记录；新格式不能靠覆盖旧档凑通过。
- 根目录test_*.py：工具链和CI观察器的Python测试。
- tools/qa/：相关行为的定向探针；按具体系统和QA记录选择。

tests/run_tests.gd同步执行注册的test_*，输出断言并非零退出失败；它不自动等待协程。若需要跨帧/信号验证，先确保runner明确等待、超时且失败传到退出码。测试必须核可观察的规则/归属/失败行为，而不是只验证没有报错。

~~~powershell
python tools/check_structure.py
python -X utf8 -m unittest discover -s tests -p "test_*.py" -v
python tools/godot.py test --test-timeout 1800
python tools/godot.py check --test-timeout 1800
~~~

check包含结构检查、导入和完整GDScript回归；按改动先选相关定向验证，同一代码包的完整回归可由对应SHA的GitHub CI承担，无须每个文件重复全套。纯文档只查结构/链接和差异。存读改动还应覆盖迁移、进行中恢复、失败不污染活世界及适用的完整停开；涉及画面须实际运行、查看截图和日志，性能须记录实际规模与测量，均不能由无头绿灯代替。

结构检查不核外部网页、历史archive、动态拼接路径或标题锚点；.tscn/资源UID及画面仍须按对应技能和引擎验证。生成日志/临时截图使用忽略目录，QA里程碑按实际证据记录，不把不存在的日志当通过。
