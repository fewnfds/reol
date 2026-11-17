---
name: godot-audio
description: 设计、修改或review Reol的战斗音效、BGM、音量总线、并发声音与音画同步时使用；不自动扩展音乐产品功能。
---

# 音频事件、混音与并发

本地合并重写原godot-audio与audio-design；归属见[NOTICES](../../../THIRD_PARTY_NOTICES.md)。当前已有`presentation/combat_audio.gd`，从其结果去重、有限待播队列、8个voice和显示时钟接入，不为每NPC增加播放器/计时器。

- 声音消费实际且允许玩家听见的事件，和模拟提交/画面播放时刻分开；epoch换档清旧队列，同一事件不重复播放，迟到过期音不集中补播。声音和随机音色不影响世界RNG/行动。
- 并发有数量/优先级/距离或同组聚合规则，说明满voice时丢弃、抢占还是升级已有音；不能无限新建播放器或让密集普通命中挤掉重要反馈。`max_polyphony`与voice池分别核，不假定调用play就会自然混音。
- 分清线性音量与dB，零值/静音避免在`-inf`上做Tween产生NaN。用户总音量、分类音量与临时duck分层；解除duck不恢复为固定0dB覆盖玩家设置。总线名字缺失要处理，累计峰值避免削波。
- 二维空间声的监听点、衰减、相机缩放/移动和屏幕内声源要按实际AudioStreamPlayer2D规则试听；主界面/UI音用非空间声，不把音频可听条件误当视觉可见条件。新增规则要说明现有可见过滤是否仍合适。
- 播放进度、混音与输出延迟属于音频时钟；只有节拍/同步任务才用对应API补偿，不用渲染delta累计假装采样级准确。循环流的finished不保证退出等待，停止/换曲/销毁均有出口。
- 导入时核采样率、声道、循环边界、压缩/解码成本和授权；长音乐与短音效按实际需求选择流式/内存，不能仅从文件尺寸推运行内存。生成/替换音频仍需听真实输出。

验证密集事件、同组重复、音量为零后恢复及换档取消；最终试听音量/削波/疲劳和重要反馈是否能分辨。播放器触发计数能证明调度，headless/截图不能证明声音品质。

官方依据：[Audio buses](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html)、[音画同步](https://docs.godotengine.org/en/4.7/tutorials/audio/sync_with_audio.html)。
