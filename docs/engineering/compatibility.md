# 当前模型与存档支持

类型：存读实现边界。可靠加载的基础要求见[constraints](constraints.md#模拟完整性)，管线见[persistence](architecture/04-persistence.md)。本页不规定完整迁移矩阵或每次开发的验证流程。

只维护一个当前运行模型和写档格式。旧数据如果在明确支持范围内，转换后进入当前模型；不为了历史fixture永久叠加解释器或保留两套世界。不支持的格式明确拒绝，原文件和活会话保留。

实际版本数字唯一登记在[BASELINE](../status/baseline.md#代码与采用版本)，以`SessionSaveSchema`、`RegionalSimulation`、`ReolContentBundle`及领域schema为代码依据。能被某低层解析器读取，不等于普通联合会话支持该版本。

当前根schema只接受当前格式；历史拒绝分别可能给出`legacy_actions`、`legacy_events`、`legacy_buildings`、`legacy_environment`或`unsupported_version`。装配不从当前磁盘补造旧世界缺失的规则/物资/经历；旧内容清单可解析也不能因此拼成合法当前会话。

当前根版本内的旧认识账本仍可读取。它在独立候选中按原格式核对事件、见证和转述，再转换到当前表示；旧档的两份本地认识内容须一致。写档只使用当前认识格式，原档不因读取而改写。

恢复经`WorldSessionSnapshot`独立构造内容、地图、区域和引用候选，验证成功才替换。档内生成描述可重建基底，已发生变化和在途责任来自原档；派生空间/来源缓存从原事实重建。未完成边界如何保存由存读管线实际接口决定。

改变支持范围时，更新本页与实际拒绝/导入入口，按改变的路径验证。原fixture只是历史来源，不是永远支持旧版的承诺；退役源码与证据由Git/archive追溯，不另建永久兼容队列。
