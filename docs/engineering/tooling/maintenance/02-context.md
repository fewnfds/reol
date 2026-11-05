# AI开发基础设施：来源、更新与上下文预算：技能与工具上下文开销

## 4. 几十个Skill是否占很多提示词

**有开销，但通常不是37份正文一起常驻。** Codex先用名称、description和路径发现技能，选中才读`SKILL.md`，参考文件再按需读。当前官方说明还给发现目录设默认预算：模型上下文的2%，未知容量时为8,000字符；目录过大先缩短描述，仍过大可能略去部分项并提示。`skills.max_context_tokens`可调整发现目录预算，但不限制选中后正文的大小。[官方机制](https://learn.chatgpt.com/docs/build-skills)、[配置项](https://learn.chatgpt.com/docs/config-file/config-reference)

按项目规则按需选取技能，具体入口与验证方式见项目 AGENTS；字符、字节和 token 不可直接互换。

## 5. MCP、日志和长文档的成本

日志使用游标、尾部或首错；场景树分页，画面验收时再取截图。先核对实际工具发现与权限，保留场景、运行、日志和截图所需能力；工具目录大小不能直接换算为每轮 token 或费用。
