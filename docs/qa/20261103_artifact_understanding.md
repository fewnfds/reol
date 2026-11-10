# 同物异观、请人检查与强注风险：实际验收

2026-11-03。W3-a已交付；规则范围见[工作包](https://github.com/fewnfds/reol/blob/8c3deaa972f932e999167b61ea6b166b928cfe5f/docs/archive/specifications/artifact_understanding.md)，当前构建数字仅在[BASELINE](../status/baseline.md)维护。

同一温火石增加真实裂损。苏芷的药炉修补经历支持辨材，陈守拙的温石经历支持操纵；二者不共享知识，境界不作专业理解钥匙。杂役仍可实际循纹探查。描述由`SimArtifactUnderstanding`只读投影已有个人经历、观察和在场听到的具名说明；展开不学习，别人说出结论不复制操作方法。

附近选中同门可以请求辨材或探查。请求使用原社会记忆规则，当前工作、精力和有向关系决定接受与否，同条件连点不重掷。对方实际占用身体、时间及自己的灵气；玩家手持器物时邀请仅许可此次检查，不授予拿走/使用权。完成时仍附近且能交流才听到，离开不补发。公开人物活动只说“刚结束辨看石材接缝”，私人结论只由本人或实际听者的器物页呈现。

实际I页取石，首次请苏芷时她正运粮而拒绝；`user://qa_material_advice_pending.json`记录这次拒绝，不能当成进行中检查。交粮后真实点击请求，开始120000ms辨材；1027100ms、已做500ms保存到`user://qa_material_advice_active.json`，原样复制为`tests/fixtures/session_v10.json`（136184字节）。再120000ms至1147100ms，玩家听到苏芷关于细裂的说明，仍不懂操纵。完全停开后正常载入同档、同样推进，规范化全联合散列为667070107。公开活动隐私修复前的3382654171仅是中间结果，不能与最终证据混用。

之后玩家实际循纹探查240000ms，自身灵气20→19。低负荷催火180000ms，灶房粮8→6、水7→6、饭14→20、柴保持3；石头储能4→2、裂损保持1。真实材料事务保持，不能由一句知识说明直接生饭。见`logs/understanding-before-heat.json`、`logs/understanding-after-heat.json`。

再实际强注，1567600ms保存到`user://qa_stone_overload_active.json`，原样复制为`tests/fixtures/overload_v10.json`（156980字节）。开始已付6灵气，余额11；当时体力100、裂损1、储能2。再120000ms至1687600ms，裂损4、储能0、灵气11，14点反噬后半秒恢复4，体力90。完全停开、正常读同档再推进，规范化全联合散列仍206336746。破石保留，不因读档复原。证据`logs/stone-overload-completed.json`、`logs/stone-overload-restart.json`。

最终画面1280×720：`logs/stone-overload-final-20261103.png`、`logs/material-advice-final-private-20261103.png`。后者实际点击苏芷再按I，同门HUD只显示公开活动，器物页保留具名私人说明；长内容在滚动区内。最终检查另存`logs/material-advice-final-private.json`。旧图`material-advice-completed-visible-20261103.png`在隐私修复前，不能作为最终隐私验收。取证时一次对旧运行进程调用新`status`参数产生eval错误；完整重启加载当前脚本后两参数接口及同一散列确认正常，新run67启动无项目错误。

自动覆盖三观察者差异、查询不变更状态、陈旧认识、未在场听不到、邀请权限、拒绝重掷、低负荷实物投入、强注/取消、粗细时间、JSON进行中与坏快照原子拒绝。根schema10/区域快照7/器物3，v9及更旧显式链迁移；旧物裂损0、背景空、听者空，不倒造经历。真实v1–v10文件保留原样。

边界：专用温石规则；没有通用热力学、修复、永久人体伤势、死亡、无界鉴定或创法。强注后体力恢复不等于永久伤亡已完成，W3-a不代表整个游戏或所有U场景通过。
