# 有限交谈与个人能力自述验收

> 历史资料：保留原日期与结果，不是现行指令或任务；当前信息查[项目记忆地图](../../README.md)。归档于2026-11-11。

2026-11-03。范围见[规格](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/capability_conversation.md)，完整检查结果由[BASELINE](../../status/baseline.md)维护，原完整游戏Goal继续active。

## 已接行为与限制

人身C选择“交流：询问能帮什么”、公开话题“你平日能帮些什么？”。接收者仍须在场、能通信且理解口头问话；复杂自述不由手势直接翻译，鸟/山兽不变成服务目录。原社会判断按关系、精力/忙闲决定是否介绍，原专注/睡眠/身体任务优先，普通搬运可短答且不中断。相同条件复用原决定和原答复，不每次点击掷骰。

自述投影本人普通搬运、日常做饭、辨材背景、实际温石基础及当前任职；不查仓库预算或他人的秘技。介绍不授予听者掌握/权限/物资，不担保接下一项请求。答复只存原社会账里的双方私下事件，旁人不获内容；跨聚落访客使用已有服务社会账，不复制人或记忆库。重新打开C/读档仅回想本人收到的旧话，换任后的说法须再次当面询问。

SimCapabilityConversation是无状态协作者，规则在data；没有新领域/动作队列/钱包。根26/区域23/服务5保持不变，旧档无自述则不补造。候选核对话题/白名单内容、双方/时刻、私下社会决定、事件与决定双向引用；声称本身不成为执行授权。

这是单话题/白名单自述，尚无通用自然语言、多轮追问、自动撒谎/宣传或完整能力推理；NPC可用同API发问，但没有自主交谈目标规划。C原辨物/交易/差事仍能单独提出，不强迫每次先问介绍。

## 自动验证

`tests/sim/test_capability_conversation.gd`与`tests/runtime/test_capability_conversation_runtime.gd`覆盖新人/灶上日常/辨材/操纵/任职、原实际学习后改变自述、旧话不追随换任、本人来源/旁人不可读、不传技能/权限/库存、远方/手势/鸟/专注/敌意拒绝、缓存不重掷、NPC同接口、跨聚落相同未来、坏文本/决定引用原子拒绝及真实旧/新档接续。定向命令`godot --headless --path . --script res://tools/qa/conversation_probe.gd`最终72断言/0失败，日志`logs/conversation-probe-20261103.log`。

首轮运行测试漏写测试辅助`_canonical`，Godot报Parse Error；已补齐并重新跑到真实运行组和真实档，不能用首轮“48/0”冒充成功。完整检查见BASELINE。

## 真实输入、保存与完整停开

run147以真实鼠标点击杂役开局，C口头询问阿禾，再鼠标下拉选择陈守拙/提出请求；没有调用ask注入答复，没有注钱货、瞬移或关闭NPC自主。阿禾介绍日常米水做饭，陈守拙介绍温石和原公库/核簿/通行任职；说明仍要另核预算。C进度改为100px高可滚动RichTextLabel，长话不挤出1280×720面板，已实际鼠标滚轮从0滚到60（内容160px/窗口100px），底部说明可读。

正常共同时间推进1001ms后保存`user://qa_conversation_20261103.json`，原样复制`tests/fixtures/conversation_v26.json`，130279字节，SHA256 `d493d2c58815eaf289ebd5a91399a86cd0ab07514dedcc0eb9e59f73d77d342a`。两条自述为原home:event_1/2，后台无钱货变化；阿禾正在原温石研究，原job保留previous_autonomous=true，并非关闭自主。

原进程继续180000ms到181001ms，全联合规范化JSON88174字节/散列2750236690。完整停止run147、run148重开加载同档，C恢复陈守拙原话，再180000ms全联合JSON逐字一致。对照`logs/conversation-future-20261103.json`与`conversation-restarted-20261103.json`。普通游戏档未覆盖，旧v1～v26、wage_claim_v26/overload_v10及本真实档均不可重写。

截图：`logs/conversation-ahe-clicked-20261103.png`、`conversation-chen-clicked-20261103.png`、`conversation-restarted-20261103.png`。这些验证实际问答与滚动布局，不把截图中间歇缺失的其他元素写成已修复。

## 呈现调查接续：恢复原D3D12，缺失问题未结案

前一包Vulkan多次重启/读档未复现后保留，随后run146工具截图又显示部分文字/按钮缺少；同一静止画面直接保存的连续8帧则完整、PNG的SHA256相同（前16位57aac47c080f9101）。原D3D12及后续直接截图也曾有缺少元素，不能证明只由工具传输造成。此证据不足以认定字体或后端是根因。

项目已恢复原Windows D3D12覆盖，最终run147/148实测d3d12/Forward+；没有留下SystemFont/字体缓存或批缓冲补丁。Vulkan同机性能和相同未来报告仍保留在[前包QA](20261103_budgeted_labor.md)，只是对照记录。临时独立Compatibility对照45秒超时，未取得成功图像、未改项目renderer；不据此更换引擎/后端/插件。Context7及官方仓库搜索未找到可确认本项目根因的证据，不引入网络补丁。

之后需用可独立复现的固定画面分离布局、CanvasItem提交与截图路径；不能仅凭一次干净截图宣布修好。当前工作包的行为、存读和因果验证成立，呈现缺失作为明确未解决项保留。
