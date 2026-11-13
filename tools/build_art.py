#!/usr/bin/env python3
"""Rebuild the temporary pixel pack from checked-in sources (Pillow only).

No model, network, engine or save access. Source prompts/provenance stay beside
the generated source images. Runtime consumes the resulting catalog/atlases.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps
from pixel_fixtures import fixture, wall, door

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/art"
SOURCE = OUT / "source"
THIRD = ROOT / "assets/third_party/kenney"
INK = "#202b3d"
TEAL = "#438b78"
GOLD = "#dca453"
CREAM = "#f1dfaf"
WOOD = "#956443"
CLIPS = ["idle", "walk", "carry", "harvest", "build", "craft", "melee", "shoot", "hurt", "rest", "eat", "read", "meditate", "fly", "dead", "water"]
LABELS = ["待机", "行走", "搬运", "采集/砍伐", "施工", "加工/烹饪", "近战", "弓箭", "受击", "休息", "进食", "读书/交谈", "修行", "飞行", "死亡", "浇灌"]
WORLD_KEYS = ["oak", "pine", "dead_tree", "stump", "rock", "flower_bush", "cactus", "lotus", "chest", "bed", "table", "chair", "stove", "workbench", "furnace", "planter", "wall_preview", "door_preview", "window", "roof_preview", "well", "water_jar", "campfire", "grave", "cushion", "incense", "bookcase", "lantern", "alchemy", "loom", "screen", "go_board"]
WORLD_LABELS = ["阔叶树", "松树", "枯树", "树桩", "矿石", "花灌木", "沙生刺", "荷花", "储物箱", "床", "桌", "椅", "灶台", "工作台", "炉", "花盆", "墙样稿", "门样稿", "窗", "屋面样稿", "井", "水缸", "篝火", "墓", "蒲团", "香炉", "书柜", "灯", "炼丹炉", "织机", "屏风", "棋盘"]
FAUNA = ["chicken", "rabbit", "sheep", "cow", "boar", "fox", "wolf", "deer", "crane", "butterfly", "slime", "ghost", "tree_spirit", "golem", "demon", "flying_sword"]
FAUNA_LABELS = ["鸡", "兔", "羊", "牛", "野猪", "狐", "狼", "鹿", "鹤", "蝶", "玉液怪", "灵体", "树精", "石傀儡", "小妖", "飞剑"]


def pixels(image: Image.Image):
    """Pillow 10-13; getdata was renamed in 13."""
    return image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()


def isolate(image: Image.Image) -> Image.Image:
    """Flood only white connected to the border; preserve enclosed white fur."""
    image = image.convert("RGBA")
    mask = Image.new("RGB", image.size)
    mask.putdata([(255, 255, 255) if min(r, g, b) > 228 and max(r, g, b) - min(r, g, b) < 25 else (0, 0, 0) for r, g, b, _ in pixels(image)])
    for x in range(image.width):
        for y in [0, image.height - 1]:
            if mask.getpixel((x, y)) == (255, 255, 255):
                ImageDraw.floodfill(mask, (x, y), (255, 0, 255))
    for y in range(image.height):
        for x in [0, image.width - 1]:
            if mask.getpixel((x, y)) == (255, 255, 255):
                ImageDraw.floodfill(mask, (x, y), (255, 0, 255))
    alpha = Image.new("L", image.size)
    alpha.putdata([0 if p == (255, 0, 255) else 255 for p in pixels(mask)])
    image.putalpha(alpha)
    # Generated gutters are approximate; remove disconnected neighbour slivers.
    visited: set[tuple[int, int]] = set()
    components: list[list[tuple[int, int]]] = []
    for y in range(image.height):
        for x in range(image.width):
            if (x, y) in visited or alpha.getpixel((x, y)) == 0:
                continue
            stack = [(x, y)]; visited.add((x, y)); component = []
            while stack:
                xx, yy = stack.pop(); component.append((xx, yy))
                for nx, ny in [(xx-1, yy), (xx+1, yy), (xx, yy-1), (xx, yy+1)]:
                    if 0 <= nx < image.width and 0 <= ny < image.height and (nx, ny) not in visited and alpha.getpixel((nx, ny)):
                        visited.add((nx, ny)); stack.append((nx, ny))
            components.append(component)
    if components:
        major = max(components, key=len)
        bounds = (min(p[0] for p in major), min(p[1] for p in major), max(p[0] for p in major), max(p[1] for p in major))
        for component in components:
            if component is major:
                continue
            cx = sum(p[0] for p in component)/len(component); cy = sum(p[1] for p in component)/len(component)
            if not (bounds[0]-8 <= cx <= bounds[2]+8 and bounds[1]-12 <= cy <= bounds[3]+8):
                for p in component:alpha.putpixel(p, 0)
        image.putalpha(alpha)
    return image.crop(image.getbbox())


def pixelize(image: Image.Image, max_size: tuple[int, int], colors: int = 28) -> Image.Image:
    ratio = min(max_size[0] / image.width, max_size[1] / image.height)
    size = (max(1, round(image.width * ratio)), max(1, round(image.height * ratio)))
    image = image.resize(size, Image.Resampling.LANCZOS)
    alpha = image.getchannel("A").point(lambda p: 255 if p > 155 else 0)
    image = image.convert("RGB").quantize(colors, dither=Image.Dither.NONE).convert("RGBA")
    image.putalpha(alpha)
    # Resampling/thresholding can leave transparent rows below the feet. Crop
    # again before Pack.add aligns the sprite to its catalog anchor.
    return image.crop(image.getbbox()) if image.getbbox() else image


def cells(path: Path, columns: int, rows: int, row_edges: list[int] | None = None, gutters: bool = False) -> list[Image.Image]:
    image = Image.open(path)
    edges = row_edges or [round(y * image.height / rows) for y in range(rows+1)]
    result = []
    for y in range(rows):
        splits = [round(x * image.width / columns) for x in range(columns+1)]
        if gutters:
            # Use actual white gaps BEFORE cropping an approximate model grid.
            rgb = image.crop((0, edges[y], image.width, edges[y+1])).convert("RGB")
            occupied = [any(min(rgb.getpixel((x, yy))) < 228 for yy in range(rgb.height)) for x in range(rgb.width)]
            runs = []; start = None
            for x, solid in enumerate(occupied + [False]):
                if solid and start is None:start = x
                if not solid and start is not None:runs.append((start,x));start = None
            if len(runs) != columns:
                raise ValueError(f"{path.name} row {y}: expected {columns} silhouettes, found {len(runs)}")
            splits = [0] + [(runs[x-1][1]+runs[x][0])//2 for x in range(1,columns)] + [image.width]
        for x in range(columns):
            result.append(isolate(image.crop((splits[x],edges[y],splits[x+1],edges[y+1]))))
    return result


def blank(size: int = 48) -> Image.Image:
    return Image.new("RGBA", (size, size))


def tool(draw: ImageDraw.ImageDraw, kind: str, x: int, y: int, frame: int) -> None:
    angle = [-0.7, -0.15, 0.65, 0.15][frame]
    ex, ey = x + round(math.sin(angle) * 10), y - round(math.cos(angle) * 10)
    draw.line((x, y, ex, ey), fill=INK, width=3)
    draw.line((x, y, ex, ey), fill=WOOD, width=1)
    if kind in ["build", "craft"]:
        draw.rectangle((ex - 3, ey - 1, ex + 3, ey + 2), fill="#6c8990", outline=INK)
    else:
        draw.polygon([(ex - 4, ey - 2), (ex + 1, ey - 4), (ex + 3, ey + 1), (ex - 3, ey + 2)], fill="#b8c6be", outline=INK)


def actors() -> dict:
    views = [pixelize(im, (25, 34), 24) for im in cells(SOURCE / "character.png", 4, 2)]
    # The generated SW was another SE. Correct the facing explicitly; this is
    # a temporary mirrored view, not an anatomical-equipment reference rig.
    views[5] = ImageOps.mirror(views[3])
    atlas = Image.new("RGBA", (48 * 32, 48 * len(CLIPS)))
    for direction, base in enumerate(views):
        for action, clip in enumerate(CLIPS):
            for frame in range(4):
                im = blank()
                bob = [0, -1, 0, -1][frame] if clip in ["walk", "carry", "fly"] else [0, 0, -1, 0][frame]
                x, foot = 24 - base.width // 2, 42
                body = base.copy()
                if clip in ["walk", "carry"]:
                    # Boots move independently while the body retains a stable
                    # baseline; translational travel still comes from simulation.
                    body.paste((0, 0, 0, 0), (0, body.height - 4, body.width, body.height))
                    im.alpha_composite(body, (x, foot - base.height + bob))
                    for half in range(2):
                        boots = base.crop((half * (base.width // 2), base.height - 4, (half + 1) * (base.width // 2), base.height))
                        im.alpha_composite(boots, (x + half * (base.width // 2), foot - 4 + ([0, -1, 0, 1][frame] * (1 if half else -1))))
                elif clip == "dead":
                    body = base.rotate(90, expand=True, resample=Image.Resampling.NEAREST)
                    # Frozen corpse pose, never a looping standing idle.
                    im.alpha_composite(body, (24 - body.width // 2, 42 - body.height))
                elif clip == "rest":
                    body = base.rotate(90, expand=True, resample=Image.Resampling.NEAREST)
                    im.alpha_composite(body, (24 - body.width // 2, 38 - body.height))
                else:
                    if clip in ["harvest", "build", "craft", "melee", "water"] and frame == 2:
                        body = body.resize((body.width + 1, body.height - 2), Image.Resampling.NEAREST)
                    if clip == "meditate":
                        body = body.crop((0, 0, body.width, body.height - 4))
                    im.alpha_composite(body, (24 - body.width // 2, foot - body.height + bob))
                d = ImageDraw.Draw(im)
                hand_x = 31 if direction in [0, 1, 2, 3, 4] else 16
                if clip == "carry":
                    d.rectangle((17, 27, 31, 38), fill=WOOD, outline=INK)
                    d.line((18, 29, 30, 37), fill=GOLD, width=2)
                    d.line((30, 29, 18, 37), fill=GOLD, width=2)
                elif clip in ["harvest", "build", "craft"]:
                    tool(d, clip, hand_x, 31, frame)
                elif clip == "melee":
                    angle = [-0.9, -0.2, 0.9, 0.3][frame]
                    end = (hand_x + round(math.sin(angle) * 13), 28 - round(math.cos(angle) * 13))
                    d.line((hand_x, 31, *end), fill=INK, width=4)
                    d.line((hand_x, 30, *end), fill="#c6d5d1", width=2)
                    d.line((hand_x - 3, 28, hand_x + 3, 30), fill=GOLD, width=2)
                elif clip == "shoot":
                    xx = 34 if hand_x > 24 else 13
                    d.arc((xx - 4, 19, xx + 4, 37), 260 if hand_x > 24 else 80, 100 if hand_x > 24 else 280, fill=GOLD, width=2)
                    d.line((xx, 20, xx - 4 if frame == 1 else xx, 28, xx, 36), fill=CREAM, width=1)
                elif clip == "water":
                    d.rectangle((hand_x - 4, 29, hand_x + 4, 35), fill="#619db5", outline=INK)
                    d.line((hand_x, 29, hand_x + 9, 34), fill="#b0d4d1", width=2)
                elif clip in ["read", "eat"]:
                    color = "#d6b57f" if clip == "read" else "#d69c67"
                    d.rectangle((17, 27, 31, 35), fill=color, outline=INK)
                    d.line((24, 28, 24, 34), fill=CREAM, width=1)
                elif clip == "meditate":
                    d.ellipse((14, 37, 34, 43), fill=TEAL, outline=CREAM)
                elif clip == "fly":
                    d.polygon([(8, 44), (38, 44), (44, 40), (36, 41)], fill="#d7b661", outline=INK)
                elif clip == "hurt" and frame < 2:
                    # Visible but no long white-screen flash.
                    glow = Image.new("RGBA", im.size, (232, 128, 101, 120))
                    glow.putalpha(im.getchannel("A").point(lambda p: 100 if p else 0))
                    im = Image.alpha_composite(im, glow)
                atlas.alpha_composite(im, ((direction * 4 + frame) * 48, action * 48))
    atlas.save(OUT / "actors.png", optimize=True)
    sheet = Image.new("RGB", (8 * 128, len(CLIPS) * 112), "#273b38")
    d = ImageDraw.Draw(sheet)
    for action, name in enumerate(CLIPS):
        for facing in range(8):
            im = atlas.crop(((facing * 4 + 1) * 48, action * 48, (facing * 4 + 2) * 48, (action + 1) * 48)).resize((96, 96), Image.Resampling.NEAREST)
            sheet.paste(im, (facing * 128 + 16, action * 112), im)
        d.text((4, action * 112 + 96), name, fill=CREAM)
    sheet.save(OUT / "actor_contact.png", optimize=True)
    return {"texture": "res://assets/art/actors.png", "frame_size": 48, "origin": [24, 42], "columns": 32, "directions": ["N", "NE", "E", "SE", "S", "SW", "W", "NW"], "frames_per_clip": 4,
            "clips": [{"id": clip, "label": LABELS[i], "row": i, "period_ms": 900 if clip != "idle" else 1600, "loop": clip not in ["dead", "hurt"]} for i, clip in enumerate(CLIPS)],
            "note": "SW direction corrected by mirroring SE; equipment later needs authored anatomical attachment; derived action frames are temporary cutout animation."}


class Pack:
    def __init__(self) -> None:
        self.images: list[Image.Image] = []
        self.entries: dict = {}

    def add(self, key: str, image: Image.Image, label: str = "", category: str = "objects", state: str = "ready", source: str = "authored", anchor: tuple[int, int] = (32, 52), footprint: tuple[int, int] | None = None) -> None:
        if image.size != (64, 64):
            image = image.crop(image.getbbox())
            image.thumbnail((56,48),Image.Resampling.NEAREST)
            image = image.crop(image.getbbox())
            normalized = Image.new("RGBA", (64, 64))
            normalized.alpha_composite(image, (anchor[0] - image.width // 2, anchor[1] - image.height + 1))
            image = normalized
        slot = len(self.images)
        self.images.append(image)
        self.entries[key] = {"slot": slot, "rect": [slot % 8 * 64, slot // 8 * 64, 64, 64], "anchor": list(anchor), "label": label or key, "category": category, "state": state, "source": source}
        if footprint:self.entries[key]["footprint"] = list(footprint)

    def save(self) -> None:
        atlas = Image.new("RGBA", (512, math.ceil(len(self.images) / 8) * 64))
        sheet = Image.new("RGB", (8 * 128, math.ceil(len(self.images) / 8) * 145), "#2a3f3d")
        d = ImageDraw.Draw(sheet)
        for i, image in enumerate(self.images):
            atlas.alpha_composite(image, (i % 8 * 64, i // 8 * 64))
            big = image.resize((128, 128), Image.Resampling.NEAREST)
            sheet.paste(big, (i % 8 * 128, i // 8 * 145), big)
            key = next(k for k, e in self.entries.items() if e["slot"] == i)
            d.text((i % 8 * 128 + 2, i // 8 * 145 + 128), key[:21], fill=CREAM)
        atlas.save(OUT / "world.png", optimize=True)
        sheet.save(OUT / "world_contact.png", optimize=True)


def world() -> dict:
    pack = Pack()
    generated = cells(SOURCE / "world.png", 8, 4, gutters=True)
    for i, image in enumerate(generated):
        if i >= 8:
            art, footprint = fixture(WORLD_KEYS[i])
            for facing in range(4):
                rotated = art.rotate(-90*facing, resample=Image.Resampling.NEAREST, center=(32,32))
                occupied = footprint[::-1] if facing % 2 else footprint
                pack.add(WORLD_KEYS[i] if facing == 0 else f"{WORLD_KEYS[i]}_{facing}", rotated, WORLD_LABELS[i]+f" · {['N','E','S','W'][facing]}", anchor=(32,32), footprint=occupied)
            continue
        maximum = (30, 30) if i not in [0, 1, 2] else (30, 38)
        image = pixelize(image, maximum)
        image = image.resize((image.width * 2, image.height * 2), Image.Resampling.NEAREST)
        image.thumbnail((56,48),Image.Resampling.NEAREST)
        pack.add(WORLD_KEYS[i], image, WORLD_LABELS[i], source="generated:world")
    art, footprint = fixture("long_bed")
    for facing in range(4):
        rotated = art.rotate(-90*facing, resample=Image.Resampling.NEAREST, center=(32,32))
        pack.add("long_bed" if facing == 0 else f"long_bed_{facing}",rotated,"长床 · "+['N','E','S','W'][facing],anchor=(32,32),footprint=footprint[::-1] if facing%2 else footprint)
    for i, image in enumerate(cells(SOURCE / "fauna.png", 4, 4)):
        small = pixelize(image, (24, 28))
        pack.add(FAUNA[i], small.resize((small.width * 2, small.height * 2), Image.Resampling.NEAREST), FAUNA_LABELS[i], category="creatures", state="reserve", source="generated:fauna")
    plant_sources = cells(SOURCE / "plants.png", 5, 6, [0, 192, 352, 507, 651, 800, 1024], gutters=True)
    plant_names = json.loads((ROOT / "data/definitions/plants.json").read_text(encoding="utf-8"))["types"]
    stages = ["播种", "幼苗", "成熟", "残株", "枯萎"]
    for row, name in enumerate(["perennial_herb", "annual_grass", "fire_herb", "lotus", "desert_thorn", "old_tree"]):
        for stage in range(5):
            sizes = [(12, 5), (12, 13), (26, 25), (20, 10), (18, 18)]
            if name == "old_tree":sizes = [(12, 6), (16, 18), (32, 28), (23, 15), (25, 28)]
            image = pixelize(plant_sources[row*5+stage], sizes[stage])
            image = image.resize((image.width*2, image.height*2), Image.Resampling.NEAREST)
            image.thumbnail((56,48),Image.Resampling.NEAREST)
            pack.add(f"{name}_{stage}", image, label=f"{plant_names[name]['label']} · {stages[stage]}", category="plants", source="generated:plants")
    # Walls cover their entire blocked cell; no half-cell offset or extrusion.
    for mask in range(16):
        pack.add(f"wall_{mask}", wall(mask), category="structures", anchor=(32,32), footprint=(1,1))
    for vertical in [False,True]:
        pack.add("door_v" if vertical else "door", door(vertical), "东西通路" if vertical else "南北通路",category="structures",anchor=(32,32),footprint=(1,1))
    im=blank(64);d=ImageDraw.Draw(im)
    d.rectangle((16,16,47,47),fill="#5e7c89")
    for y in range(18,48,6):d.line((16,y,47,y),fill="#a6bac1")
    pack.add("roof", im, "屋顶层",category="structures",anchor=(32,32),footprint=(1,1))
    items = {"wood": ("tiny-town", 106), "stone": ("tiny-farm", 89), "grain": ("tiny-farm", 32), "herb": ("tiny-farm", 29), "potion": ("tiny-dungeon", 116), "fruit": ("tiny-farm", 41), "sword": ("tiny-dungeon", 105), "bow": ("tiny-town", 118), "hoe": ("tiny-farm", 87), "staff": ("tiny-dungeon", 127)}
    for name, (source, index) in items.items():
        image = Image.open(THIRD / source / f"tile_{index:04d}.png").convert("RGBA")
        image = image.resize((32, 32), Image.Resampling.NEAREST)
        pack.add("item_" + name, image, category="items", source=f"kenney:{source}/{index:04d}")
    # Small authored inventory families fill gaps in the external selection.
    for name in ["shield", "arrow", "water", "watering_can", "robe", "armor", "boots", "hat", "talisman", "spirit_stone", "egg", "fish", "meal", "dried_herb", "fiber", "lotus_seed", "lotus_root", "breath_manual", "axe", "pickaxe", "shovel", "spear", "bundle"]:
        image = blank(32); d = ImageDraw.Draw(image)
        if name == "bundle":
            d.polygon([(7,14),(13,10),(11,5),(21,5),(19,11),(26,16),(27,25),(23,28),(8,28),(5,23)],fill="#ac976d",outline=INK)
            d.line((12,11,21,11),fill=WOOD,width=3)
        elif name == "meal":
            d.ellipse((5,10,27,22),fill=INK)
            d.pieslice((5,9,27,29),0,180,fill="#849da1",outline=INK)
            d.ellipse((7,11,25,18),fill=CREAM,outline=INK)
            for x,y in [(11,13),(16,12),(21,14)]:d.rectangle((x,y,x+2,y+2),fill=TEAL)
        elif name in ["dried_herb", "fiber"]:
            for x in range(8,25,4):
                d.line((x,25,16+(x-16)//2,6),fill="#b4ad70" if name=="dried_herb" else CREAM,width=3)
                if name=="dried_herb":d.ellipse((x-2,8,x+2,15),fill="#8e9666",outline=INK)
            d.line((8,19,24,19),fill=WOOD,width=3)
        elif name == "lotus_seed":
            for x,y in [(7,14),(15,8),(22,15),(14,22)]:d.ellipse((x-3,y-3,x+3,y+4),fill="#d3bf82",outline=INK)
        elif name == "lotus_root":
            d.rounded_rectangle((5,13,27,23),radius=5,fill="#bb9171",outline=INK)
            d.ellipse((18,11,28,23),fill=CREAM,outline=INK)
            for x,y in [(22,15),(25,17),(21,19)]:d.ellipse((x-1,y-1,x+1,y+1),fill="#92704e")
        elif name == "breath_manual":
            d.rectangle((7,5,25,28),fill=INK)
            d.rectangle((9,6,24,25),fill="#648a89")
            d.rectangle((19,9,22,20),fill=CREAM)
            for y in [11,16,21]:d.line((8,y,11,y),fill=CREAM)
            d.line((10,27,24,27),fill=CREAM)
        elif name in ["axe", "pickaxe", "shovel", "spear", "bundle"]:
            d.line((10,27,21,6),fill=INK,width=4)
            d.line((10,26,20,7),fill=WOOD,width=2)
            if name == "axe":d.polygon([(18,6),(26,6),(28,15),(20,15)],fill="#a5bec0",outline=INK)
            elif name == "pickaxe":d.line((10,8,20,5,28,12),fill=INK,width=4);d.line((10,8,20,6,28,12),fill="#a5bec0",width=2)
            elif name == "shovel":d.polygon([(18,6),(22,4),(27,8),(22,17),(16,13)],fill="#a5bec0",outline=INK)
            else:d.polygon([(18,8),(25,2),(24,12)],fill="#b9cfd0",outline=INK)
        elif name == "shield":
            d.polygon([(8,5),(24,5),(23,20),(16,27),(9,20)], fill="#789aa1", outline=INK)
            d.line((16,7,16,23),fill=CREAM,width=2)
        elif name == "arrow":
            d.line((5,25,25,5),fill=WOOD,width=2);d.polygon([(20,5),(27,3),(25,11)],fill="#bbd1cb",outline=INK)
            d.line((4,20,9,26),fill=CREAM,width=2)
        elif name in ["water", "watering_can"]:
            d.rounded_rectangle((8,12,23,25),radius=3,fill="#75a9b4",outline=INK)
            d.arc((11,6,20,18),180,360,fill=INK,width=2)
            if name == "watering_can":d.polygon([(22,15),(29,11),(29,15),(23,20)],fill="#9dc1bb",outline=INK)
            else:d.line((10,14,20,14),fill="#d9e5d5",width=2)
        elif name in ["robe", "armor"]:
            d.polygon([(9,5),(14,7),(18,7),(23,5),(29,16),(24,19),(21,15),(24,27),(8,27),(11,15),(8,19),(3,16)],fill=TEAL if name=="robe" else "#8ba2a7",outline=INK)
            d.line((12,8,20,19,9,19),fill=CREAM,width=2)
            d.rectangle((9,19,23,21),fill=GOLD)
        elif name == "boots":
            for x in [5,18]:d.polygon([(x,8),(x+6,8),(x+6,20),(x+9,24),(x,24)],fill=WOOD,outline=INK)
        elif name == "hat":
            d.polygon([(3,19),(16,6),(29,19)],fill=GOLD,outline=INK);d.line((4,20,28,20),fill=CREAM,width=2)
        elif name == "talisman":
            d.rectangle((10,4,23,28),fill=CREAM,outline=INK)
            d.line((14,8,20,10,14,15,20,19,15,25),fill="#b75c4b",width=2)
        elif name == "spirit_stone":d.polygon([(16,3),(25,11),(22,25),(11,28),(6,16)],fill="#9dc9b8",outline=INK)
        elif name == "egg":d.ellipse((9,5,23,27),fill=CREAM,outline=INK)
        else:
            d.ellipse((5,10,24,22),fill="#8db7bc",outline=INK);d.polygon([(23,15),(29,9),(29,24)],fill="#5d8c9d",outline=INK);d.rectangle((9,13,11,15),fill=INK)
        current_items = {"water", "meal", "dried_herb", "fiber", "lotus_seed", "lotus_root", "breath_manual", "bundle"}
        pack.add("item_"+name, image, category="items", state="ready" if name in current_items else "reserve")
    for family, colors in [("fire", ["#e16c43", "#f0bd64"]), ("ice", ["#88c4d2", "#d2eee4"]), ("heal", ["#74c38e", "#d4e9a2"]), ("hit", ["#efcd8c", "#f4ead1"]), ("qi", ["#b09bcd", "#f0dfa3"]), ("dust", ["#a98861", "#d2ba8c"]), ("metal", ["#c9d0c0", "#fff2c2"]), ("wood", ["#5b9c76", "#afd69c"]), ("water", ["#559fba", "#b4e1d6"]), ("earth", ["#bc965c", "#ebd298"])]:
        for frame in range(4):
            im = blank(64)
            d = ImageDraw.Draw(im)
            for k in range(6):
                angle = k * math.tau / 6
                r = 4 + frame * 4
                x, y = 32 + round(math.cos(angle) * r), 35 + round(math.sin(angle) * r)
                d.rectangle((x - 2, y - 2, x + 2, y + 2), fill=colors[k % 2])
            if family in ["fire", "heal"]:
                d.polygon([(25, 39), (30, 21 - frame * 2), (33, 29), (38, 17 + frame), (40, 39)], fill=colors[0])
                d.rectangle((31, 32, 35, 39), fill=colors[1])
            pack.add(f"fx_{family}_{frame}", im, category="effects")
    pack.save()
    return pack.entries


def terrain() -> dict:
    atlas = Image.new("RGBA", (16 * 8, 16 * 4))
    colors = [("#557d60", "#668b68", "#416b52"), ("#b38d61", "#bd9b70", "#9c7958"), ("#498d9c", "#5aa3aa", "#3b7c91"), ("#859797", "#9eacaa", "#6f8589"), ("#c2ab7c", "#d2bc89", "#ab9469"), ("#987451", "#b18d61", "#7a5b43"), ("#715741", "#91704a", "#5c4839"), ("#d4dfd9", "#e8ebdc", "#a9c3c2")]
    for surface, palette in enumerate(colors):
        for variant in range(4):
            im = Image.new("RGBA", (16, 16), palette[0]);d = ImageDraw.Draw(im)
            for k in range(8):
                x, y = (k * 7 + variant * 3) % 16, (k * 11 + variant * 5) % 16
                d.line((x, y, min(15, x + 1), y), fill=palette[1 if k % 3 else 2])
            if surface == 2:
                for y in [4, 12]:
                    x = (variant * 3 + y) % 9
                    d.line((x, y, x + 5, y), fill=palette[1])
            if surface == 5:
                for y in [0, 7, 15]:d.line((0, y, 15, y), fill=palette[2])
                d.line((4 if variant % 2 else 12, 0, 4 if variant % 2 else 12, 7), fill=palette[2])
            if surface == 6:
                for x in [2, 6, 10, 14]:d.line((x, 0, x, 15), fill=palette[2])
            atlas.alpha_composite(im, (surface * 16, variant * 16))
    atlas.save(OUT / "terrain.png", optimize=True)
    return {"texture": "res://assets/art/terrain.png", "tile_size": 16, "surfaces": ["grass", "soil", "water", "cold_stone", "sand", "wood_floor", "tilled_soil", "snow"], "variants": 4, "source": "authored"}


def main() -> None:
    OUT.mkdir(exist_ok=True)
    manifest = {"schema": 1, "name": "Jade Valley temporary pixel pack", "date": "2026-11-12", "world": {"texture": "res://assets/art/world.png", "cell_size": 64, "columns": 8}, "characters": actors(), "entries": world(), "terrain": terrain()}
    for name in ["actors.png", "world.png", "terrain.png"]:
        manifest.setdefault("sha256", {})[name] = hashlib.sha256((OUT / name).read_bytes()).hexdigest()
    (OUT / "catalog.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(manifest['entries'])} world/item/effect sprites; {len(CLIPS)*8*4} actor frames; 32 terrain tiles")


if __name__ == "__main__":
    main()
