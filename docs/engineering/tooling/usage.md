# 工具链与运行入口

状态：当前操作入口。实际安装及已验范围由[AI套件实装](setup.md)维护，版本与来源/更新流程见[维护记录](maintenance.md)，代码审查/CI成本策略见[工作流](../workflow/code-review.md)。本页不重复旧竞品表或宣称导出已验。完整旧文已存[整理前快照](../../archive/documentation_consolidation_20261104/docs/TOOLCHAIN.md)。

Godot跟进最新稳定版；当前已核对的是**4.7.2**，不是永久锁定。每次升级要核对编辑器、插件、CI及导出模板的实际版本与兼容；不要自动使用dev/RC。优先[官方Windows下载](https://godotengine.org/download/windows/)的标准版，不使用.NET版。可用GODOT_BIN指向具体可执行文件；设置用户环境变量后需重启读取它的进程。

## 项目命令

~~~powershell
python tools/godot.py doctor
python tools/godot.py version
python tools/godot.py import
python tools/godot.py test --list-suites
python tools/godot.py test --suite test_environment_field_rules --test-timeout 120
python tools/godot.py test --test-timeout 1800
python tools/godot.py check --test-timeout 1800
python tools/godot.py run
python tools/godot.py editor
python tools/check_structure.py
python -X utf8 -m unittest discover -s tests -p "test_*.py" -v
python tools/setup_codex.py --check --review-model gpt-6.1-sol
~~~

check包括结构、导入和统一同步测试runner；test不替代导入，测试超时或任何首个真实脚本错误均非通过。命令及作用域、画面/存读验收见[测试入口](../../../tests/README.md)。导出到Windows还需匹配引擎的模板、实际导出预设及独立运行验证，不能凭命令存在就认定已可发布。

定向`test --suite`按完整名称选择，可重复；`check`保持全套。逐组耗时和断言增量默认写到唯一`logs/*-timings-*.jsonl`，可用`--timing-report PATH`指定。报告逐组flush，失败/超时后读一次即可，不需要扫描testlog；验证分层与GPU边界见[测试策略](../workflow/testing.md)。

## 配置和观察

- 首选实时场景连接为Godot AI：编辑器启用插件后用官方dock的Configure → Codex生成带认证的attach，重载后实际核查Reol会话、日志和运行状态；不手写端口/裸HTTP，不更改第三方addon。当前实现与过滤范围见[套件实装](setup.md)。
- python tools/setup_codex.py 补项目中的Context7和默认禁用的Coding-Solo备用入口；已存在连接和无关配置保留。仅在明确需要备用时用 --enable-backup-godot；显式 --review-model gpt-6.1-sol 设置项目审查模型，--check只验证配置而不证实握手。项目配置/备份不入库；用户级路由与认证不在此脚本中改写。
- API以当前目标版本的Godot官方文档为准，Context7可辅助查询。旧opencode.json属于旧客户端，不是Codex生效配置。
- GitHub的Python及Godot CI证据按完整受检SHA核对。仅在准备实际提交时由主代理按[CI流程](../workflow/code-review.md)集中检查一次；未终态留到下次提交，不开后台等待或派被动代理。300秒缓存是限频底线，不是轮询周期；当前无GitHub结果自动插入聊天的回调。

## 排错和升级

| 现象 | 处理 |
|---|---|
| doctor找不到Godot | 检查GODOT_BIN指向实际可执行文件，新设置后重启终端；对照安装版本，不改断言或引擎要求凑绿 |
| 新class_name未识别 | 先导入并读首个解析错误；涉及资源/场景按项目验证规则实机打开 |
| Godot AI连接失败 | 先核对打开的项目、插件/后端版本、dock和原始启动首错；官方Configure后按提示重启客户端，不猜端口；已知uv/attach排查见[实装记录](setup.md) |
| Python/磁盘/内存异常 | 先核实进程命令、归属与实时指标，不凭名字停止他人进程；必要的性能样本有时间和内存上限，见[执行计划](../../archive/specifications/world_engine_execution.md) |
| 需要新依赖/升级 | 核验用途、许可、固定版本及与当前引擎的兼容，保留回退；比较和官方来源见[维护](maintenance.md) |

纯文档工作只检查文档结构/链接与差异；不要把上述全部命令变成每次任务的强制启动脚本。
