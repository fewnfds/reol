---
name: create-game-assets
description: 制作或接入Reol纯二维精灵、图块与图集时，统一斜俯视素材并核验切片、透明、脚点与实际画面；不负责玩法逻辑。
---

# Reol二维素材接入

<!-- Adapted from awesome-gamedev-agent-skills (Apache-2.0); modified for Reol on 2026-11-17. Source and license: ../../../THIRD_PARTY_NOTICES.md. -->

先查[当前素材与重建入口](../../../assets/README.md)及相关catalog条目，不另建一份manifest。项目采用固定斜俯视二维素材、正方形逻辑地块、脚点共同排序；不是菱格等轴测，也不通过三维或整屏透视形变补救角度不合的素材。

- 同一组素材沿用视向、光线、比例和调色板。改动一组前先在实际游戏尺度与邻近原素材对比；只在缺少方向时做小样，不强制每次制作风格板或等用户批准。
- 人物脚点是连续身体位置，静物锚点是占地底边中点；贴图高度不增加地面碰撞范围。多格/多部件物体沿原catalog的footprint、anchor、offset和depth接入，不凭透明画布中心定位。
- 生成稿不能证明精确格网、真实透明或动作一致。切片、尺度、锚点和命名用确定性工具规范化；动画共用尺度和脚点，逐帧看体积、足滑、轮廓和遮挡。具体陷阱见[二维处理](references/raster-pipeline.md)。
- 保留源图/来源、许可与实际生成记录到既有资产记录；含凭据的请求留本机。联系表和报告是检查工具，正式图集仍走已有重建器，不把QA输出当运行资源。

## 按需使用的图片检查工具

从项目根运行；尺寸和色数取实际目标，以下文件参数是占位示例：

```powershell
python .agents/skills/create-game-assets/scripts/asset_report.py PATH_TO_PNG --expect-size 64x64 --require-alpha --max-colors 48 --json
python .agents/skills/create-game-assets/scripts/build_preview_sheet.py PATH_TO_PNG_1 PATH_TO_PNG_2 --out .local/art-qa/preview.png --columns 4 --cell-size 192
```

`--require-alpha`会拒绝没有透明像素的RGBA，但不能识别所有画进图片的棋盘格或混合背景，仍需看图。联系表使用最近邻缩放和棋盘底。脚本需要Pillow，缺失时再按`scripts/requirements.txt`安装；不在每次制作时重装。

图片QA后在实际游戏入口核锚点、前后遮挡、动画、边缘及常见背景上的辨识度；单图好看或报告通过不等于接入完成。实际生成方式使用本次可用的生成工具；本技能不规定模型或调用协议。
