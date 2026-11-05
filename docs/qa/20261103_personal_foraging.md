# P1-c1：自留采集验收

2026-11-03，Godot 4.7.2 / Windows。规格见[personal_foraging](../archive/specifications/personal_foraging.md)，最新完整检查/格式统一维护在[BASELINE](../status/baseline.md)。完整游戏Goal保持active。

## 实际完成

原“采集”页增加自留开关，复用四个按钮。关时原公差送库，开时原身体按新的forage定义实际走到同一有限来源、预约、劳动，完成后原行囊取得物品并自然停手；不送公库、不生成公差凭据。切换开关只影响后续意图，不转换已开始工作。已有同类物不会触发原gather的续运分支，仍要做满本次劳动。

自留拾柴/采粮/汲泉/采药的定义在`data/definitions/personal_foraging.json`，新开局装配在原village场景定义；内容一致性由SimPersonalForaging检查。它只管定义/迁移，没有第二身体、来源、库存或时钟。产物仍由SimLandResources扣真实源、SimActionExecutor执行、原SimInventory持有；正数劳动/数量与0公差贡献为校验条件。容量不足或中途取消释放预约，不采出/发物。NPC可走同一接口，但未增加自主经商计划。

## 自动与实机

`tests/sim/test_personal_foraging.gd`、`tests/runtime/test_personal_foraging_runtime.gd`覆盖四种实际产物、已有同物不跳劳动、原公差送库/凭据不变、源预约竞争/满行囊/取消、近远/粗细同一未来、进行中存读及坏定义候选原子拒绝。真实v10保持无来源/无新采集，v11原公共采粮不转用途，v19原交易不被抢执行权，v20真实自留档在新场景相同接续；旧来源文件不改写。

定向`logs/personal-foraging-probe-20261103-103802.log`通过；最终完整`python tools/godot.py check`通过：`logs/check-test-20261103-103951.log`、`logs/check-import-20261103-103946.log`，无SCRIPT ERROR/ERROR/WARNING/FAIL。场景/资源strict检查598文件、0错误/0警告；结构/链接/差异检查通过。最新数量只在BASELINE维护。

run110正常恢复原444100ms人身进度，通过采集页开自留、提交采药；原药1、药圃11、野外药源尚未采出。action:7于444100ms开始、444101ms到来源、1944101ms才结束25分钟劳动。**456445ms**正常保存时仍在work，原来源预约2、采出0、背包药1，未提前发物。`tests/fixtures/session_v20.json`原样复制`user://qa_personal_foraging_inflight_20261103.json`，157940字节，SHA256：

```text
6e306e51f366ae6f41aeb74433476e03ceceacc1a3e6fa924117efb8889a5fa2
```

截图发现开始提示仍沿旧公差文案说“到功德堂登记”，已按实际动作种类修正；最终提示“采得实物自留，不记公差贡献”，增加相应界面回归。没有改变实际采集成本或对旧档补发材料。

最终代码run111从同一真实v20再1800000ms至**2256445ms**：背包药1→3、原来源累计采出2、药圃仍11、公共凭据空、钱仍6，工作结束。完整停止并启动run112，同样读档/推进，整份规范化联合JSON逐字相同，**121417字节、散列2438546047**，SHA256：

```text
e62e2bb2a5fdb432b6a76e50690af817c68a2470f17025307db7ed69ed5fb835
```

证据`logs/personal-foraging-inflight-20261103.json`、`personal-foraging-future-20261103.json`、`personal-foraging-future-canonical-20261103.json`、`personal-foraging-restarted-20261103.json`；独立演示`user://qa_personal_foraging_completed_20261103.json`。

## 接到本地交易

在原NPC继续自主的同一世界，正常走近陈守拙，通过原C请求入口买2份饭，2446445ms本人6→2钱、随身饭0→2、公账0→4钱。再正常走近并出售2份药，2636445ms本人钱2→6、药3→1、公账4→0、药圃11→13，原野外采出仍2、贡献仍0。没有注入商店资金或关NPC自主；两笔钱来自原同一现金循环，真正增加的饭和转移的药均有库存/劳动来源。

证据`logs/personal-foraging-bought-20261103.json`、`personal-foraging-traded-20261103.json`，独立用户档`qa_personal_foraging_trade_completed_20261103.json`。此前P1-b已实际验证吃随身饭不二次收费，这里不把“买”当“吃”。

1280×720已查看`logs/personal-foraging-inflight-20261103.png`与最终`personal-foraging-final-start-20261103.png`，开关/四按钮/提示在屏内，额外一行未挤出窗口；贸易结束截图另保留`personal-foraging-traded-20261103.png`。最终run112游戏日志只有正常helper注册。收尾恢复原444100ms、人身、钱6/药1、工地空并暂停；原普通档未覆盖。

## 兼容与接续

根19→20、区域16→17；原村落/服务/来源字段版本不变。只给已有自然来源的旧世界加入未来个人动作定义，不补物品/采出/贡献，不转换既有劳动。真实v1～v20和overload_v10不可改写。

本包没有建立全部产权/保管责任，公差取消后的公物、授权取用与个人货物的处置边界仍需P1-c2接续；不能把“在包里”当最终物主模型。来源仍是少量抽象采集点，尚无逐株植物/生态/土地法、私人加工/完整产业或自主商业计划。完整游戏/切片仍未完成；无新依赖或addons修改，Goal保持active。
