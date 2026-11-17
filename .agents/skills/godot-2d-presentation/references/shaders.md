# 二维shader与GPU数据

本地重写原godot-shaders及shader-programming相关指导；归属见[NOTICES](../../../../THIRD_PARTY_NOTICES.md)。实际语法按采用的Godot版本、Compatibility/其他renderer核对，不能拿通用GLSL编译成功当`.gdshader`通过。

- 明确`VERTEX/UV/SCREEN_UV`及MODEL/CANVAS/SCREEN矩阵的空间；每个uniform的范围、颜色/标量类型、像素/格单位与CPU上传字段一致。颜色参数按渲染管线使用`source_color`，不能将数值纹理当sRGB颜色。
- `TIME`受Engine time_scale影响，不随暂停自动停止，并有rollover。需要匹配世界/显示时刻的动画使用原上传时钟，说明周期/取模/精度；不要另加每人物计时器。换档和暂停后不让旧轨迹继续跑。
- 图集子图邻域采样有明确矩形/透明留边，轮廓/模糊不越界读相邻帧；没有几何/透明留边时仅clamp UV仍会将外描边裁在quad边缘。过滤、mipmap、UV翻转及wrap与实际atlas一致；取子图大小不能用整张纹理的像素宽度冒充。
- `smoothstep`下上界保持递增，反向过渡显式用`1.0 - smoothstep(...)`。屏幕纹理使用目标版本支持的hint；不要套Godot3旧内置名。
- Material是共享Resource。每实例差异优先现有INSTANCE_CUSTOM或已用的批数据；确需独立材质才复制，不能闪一个单位却改全场，也不为每个单位复制整材质打碎合批。
- MultiMesh实例布局、buffer stride、instance_count/visible_instance_count及稀疏轨迹纹理采样保持CPU/GPU同一协议，空槽/回收也清对应值。整块提交、分区及排序按当前绘制owner核，不能为省draw call破坏遮挡/拾取。
- 透明叠层、采样次数、upload与排序都可能是瓶颈；`if`/`discard`/分支消除谁快由实际renderer/硬件测，不下“永远避免分支”的断言。可见数量减少不代表卸载真实实体。

至少实际编译并看一例含图集边缘/透明/重叠的真实画面。需要判断速度时区分CPU准备/上传与GPU片元负载，不只读FPS。

官方依据：[CanvasItem shader](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/canvas_item_shader.html)、[MultiMesh优化](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html)。
