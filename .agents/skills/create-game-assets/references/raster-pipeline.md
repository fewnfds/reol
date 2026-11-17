# 二维素材处理的易错点

<!-- Adapted from awesome-gamedev-agent-skills (Apache-2.0); modified for Reol on 2026-11-17. Source and license: ../../../../THIRD_PARTY_NOTICES.md. -->

## 切片与动作

- 先检查真实留白和轮廓；模型返回的等分网格可能不准确，按等格裁切会截断树冠、兵器或动作。共用尺度后再打包，不按每帧包围盒分别拉伸到满格。
- 精灵的像素脚点与运行时地面坐标分开。统一anchor，保留武器和冠幅需要的留白；多格家具先确定占地与整物锚点，再切部件，不靠扩大碰撞去匹配图高。
- 多朝向家具先改变平面朝向，再画向上的立面，不能把已带高度的成图直接旋转。动画看运动与暂停帧，静态联系表不能揭示足滑或节奏。
- 像素素材用最近邻和共享像素尺度；生成稿的模糊伪像素、零碎噪点及重复近似颜色需修整。调色板约束按现有风格决定，不把示例48色当全项目限制。

## 导入与画面

- Godot 4的2D过滤/重复由项目或CanvasItem设置，不是旧版图片import开关。核当前项目、MultiMesh材质与shader的真实采样；不为单图模糊擅改全局设置或像素吸附，后者可能改变已有平滑插值。
- 不把mipmap、放大或全图形变当作自动改善像素美术的办法。图集边缘留白/扩边需与实际采样一致，在运动、缩放和邻接切片中观察渗色。
- 图块先看3×3重复及真实邻接组合；装饰阴影不能误导碰撞含义。UI文字、数值和交互状态保持代码可读，不烘进贴图。
- 来源记录沿[资产页](../../../../assets/README.md)维护；有来源约束时保留原许可，不复制新的模板台账。

涉及未确认的引擎选项时查目标版本[CanvasItem](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html)与[Texture2D](https://docs.godotengine.org/en/4.7/classes/class_texture2d.html)，不照搬其他引擎或旧版本导入配方。
