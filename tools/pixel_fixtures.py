"""Reproducible oblique pixel fixtures, drawn entirely as 2D raster artwork.

Ground remains square XY at 32px/cell. Rotate the flat surface design first,
then draw its raised front; never rotate a completed oblique sprite.
"""
from PIL import Image, ImageDraw

INK = "#202b3d"
WOOD = "#956443"
LIGHT = "#cfaa70"
CREAM = "#f1dfaf"
TEAL = "#438b78"
SLATE = "#7d989f"


def _surface(key: str) -> tuple[Image.Image, tuple[int, int]]:
    image = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(image)
    footprint = (1, 2) if key == "long_bed" else ((2, 1) if key in ["table", "workbench", "go_board", "stove", "screen"] else (1, 1))
    if key in ["bed", "long_bed"]:
        top, bottom = (3, 60) if key == "long_bed" else (18, 46)
        d.rectangle((19, top, 44, bottom), fill=WOOD, outline=INK, width=2)
        d.rectangle((22, top + 3, 41, bottom - 3), fill=CREAM)
        d.rounded_rectangle((23, top + 4, 40, top + 10), radius=2, fill="#fff0ce", outline=INK)
        d.rectangle((22, top + 13, 41, bottom - 3), fill=TEAL, outline=INK)
        for x in [24, 38]:d.line((x, top + 15, x, bottom - 5), fill="#68aa90")
    elif key == "chest":
        d.rectangle((18, 22, 45, 43), fill=WOOD, outline=INK, width=2)
        d.rectangle((20, 24, 43, 40), fill=LIGHT)
        for x in [23, 38]:d.rectangle((x, 23, x + 2, 41), fill=SLATE, outline=INK)
        d.line((20, 27, 43, 27), fill=INK, width=2)

    elif key in ["table", "workbench", "go_board"]:
        d.rectangle((3, 19, 60, 45), fill=WOOD, outline=INK, width=2)
        d.rectangle((6, 22, 57, 42), fill=LIGHT)
        for y in [27, 35]:d.line((7, y, 56, y), fill=WOOD)
        if key == "workbench":
            d.rectangle((9, 24, 20, 33), fill=SLATE, outline=INK)
            d.line((38, 27, 49, 38), fill=INK, width=4)
            d.rectangle((35, 23, 43, 29), fill=SLATE, outline=INK)
        elif key == "go_board":
            for x in range(15, 50, 7):d.line((x, 23, x, 40), fill=WOOD)
            for x, y, color in [(22,28,INK),(36,35,CREAM),(43,28,INK)]:d.ellipse((x-2,y-2,x+2,y+2),fill=color)
    elif key == "chair":
        d.rectangle((22, 21, 42, 44), fill=WOOD, outline=INK, width=2)
        d.rectangle((25, 28, 39, 40), fill=LIGHT, outline=INK)
        d.rectangle((21, 39, 43, 46), fill=LIGHT, outline=INK, width=2)
    elif key == "stove":
        d.rectangle((3,18,60,46), fill="#8b8b83", outline=INK, width=2)
        d.line((5,43,58,43),fill=SLATE)
        for x in [18,44]:
            d.ellipse((x-9,22,x+9,39),fill=INK,outline=SLATE,width=2)
            d.ellipse((x-6,25,x+6,36),fill="#bd643e")
        for x in [16,40]:d.rectangle((x,42,x+5,45),fill="#f0bd64",outline=INK)
    elif key in ["furnace", "alchemy"]:
        d.rectangle((18,18,46,46),fill="#8b8b83",outline=INK,width=2)
        d.ellipse((23,21,41,39),fill=INK,outline=SLATE,width=2)
        d.ellipse((26,24,38,36),fill="#5f856d" if key=="alchemy" else "#bd643e")
    elif key in ["planter", "water_jar", "incense", "well", "campfire"]:
        d.ellipse((19, 19, 45, 45), fill=WOOD if key != "well" else SLATE, outline=INK, width=2)
        inner = "#604638" if key == "planter" else ("#78acb7" if key in ["well", "water_jar"] else INK)
        d.ellipse((23, 23, 41, 41), fill=inner, outline=LIGHT)
        if key == "incense":
            for x in [28,32,36]:d.line((x,36,x,26),fill=CREAM)
        if key == "campfire":
            d.line((25,37,39,27),fill=LIGHT,width=3);d.line((26,26,39,38),fill=LIGHT,width=3)
            d.polygon([(27,35),(30,24),(33,30),(36,25),(38,35)],fill="#e16c43")
            d.rectangle((31,31,34,36),fill="#f0bd64")
    elif key == "bookcase":
        d.rectangle((18, 20, 46, 44), fill=WOOD, outline=INK, width=2)
        for y in [24, 34]:
            for x, color in [(22,TEAL),(27,CREAM),(33,SLATE),(39,"#b8604a")]:d.rectangle((x,y,x+3,y+6),fill=color,outline=INK)
    elif key == "loom":
        d.rectangle((19,18,45,46),fill=WOOD,outline=INK,width=2)
        d.rectangle((23,22,41,42),fill=CREAM,outline=INK)
        for x in range(25,42,3):d.line((x,22,x,41),fill=TEAL)
        d.line((21,36,44,36),fill=LIGHT,width=3)
    elif key == "screen":
        for x in [4,23,42]:
            d.rectangle((x,23,x+17,42),fill=WOOD,outline=INK)
            d.rectangle((x+2,25,x+15,39),fill=CREAM)
            d.line((x+3,37,x+6,29),fill=TEAL)
    elif key in ["window", "wall_preview", "door_preview", "roof_preview"]:
        d.rectangle((16,16,47,47),fill=WOOD,outline=INK,width=2)
        if key in ["window", "door_preview"]:
            d.rectangle((21,20,42,43),fill=CREAM,outline=INK,width=2)
            d.line((32,21,32,42),fill=WOOD,width=2)
            d.line((22,31,41,31),fill=WOOD,width=2)
    elif key == "grave":
        d.rounded_rectangle((22,18,42,45),radius=5,fill=SLATE,outline=INK,width=2)
        d.rectangle((25,27,39,39),fill="#a5b8b0",outline=INK)
        d.line((29,31,35,31),fill=INK)
    elif key == "cushion":
        d.ellipse((18,22,46,44),fill=TEAL,outline=INK,width=2)
        d.ellipse((23,26,41,39),fill=CREAM,outline=LIGHT)
    elif key == "lantern":
        d.rectangle((29,22,35,43),fill=WOOD,outline=INK)
        d.rounded_rectangle((24,20,40,36),radius=3,fill="#e9be62",outline=INK,width=2)
        d.line((28,23,28,32),fill=CREAM,width=2)
    else:
        raise ValueError(f"No authored fixture: {key}")
    return image, footprint



def fixture_height(key: str) -> int:
    height = 10
    if key in ["stove", "furnace", "alchemy", "chest", "well", "water_jar"]: height = 16
    if key in ["bookcase", "screen", "lantern", "grave"]: height = 22
    if key in ["cushion", "campfire", "incense"]: height = 4
    if key == "roof_preview": height = 0
    return height


def fixture(key: str, facing: int = 0) -> tuple[Image.Image, tuple[int, int]]:
    surface, footprint = _surface(key)
    surface = surface.rotate(-90 * facing, resample=Image.Resampling.NEAREST, center=(32, 32))
    if facing % 2: footprint = footprint[::-1]
    depth = footprint[1] * 32
    image = Image.new("RGBA", (64, depth + 24))
    height = fixture_height(key)
    alpha = surface.getchannel("A")
    side = Image.new("RGBA", surface.size, "#654b3a" if key not in ["stove", "furnace", "well"] else "#536571")
    side.putalpha(alpha)
    origin = 24 + depth // 2 - 32
    for lift in range(height): image.alpha_composite(side, (0, origin - lift))
    image.alpha_composite(surface, (0, origin - height))
    d = ImageDraw.Draw(image)
    # Front detail is authored in image space and follows the operating side.
    if key == "chest" and facing == 0:
        d.rectangle((19, origin + 27, 44, origin + 43), fill=WOOD, outline=INK)
        for x in [23, 38]: d.rectangle((x, origin + 28, x + 2, origin + 42), fill=SLATE)
        d.rectangle((30, origin + 29, 34, origin + 35), fill="#e6c665", outline=INK)
    if key == "stove" and facing == 0:
        d.rectangle((23, origin + 30, 41, origin + 43), fill=INK, outline=SLATE)
        d.polygon([(28, origin+40), (30, origin+34), (33, origin+38), (36, origin+33), (37, origin+40)], fill="#e08b48")
    return image, footprint


def wall(mask: int) -> Image.Image:
    """Full square ground footprint with a 20px raised face above it."""
    image = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(image)
    # Ground rect x=16..47, y=24..55; top surface is shifted upwards.
    d.rectangle((16, 4, 47, 35), fill="#b29468")
    for y in [8, 16, 24, 32]: d.line((16, y, 47, y), fill="#cfb584")
    if not mask & 4:
        d.rectangle((16, 36, 47, 55), fill="#805b40")
        for y in [40, 48]:
            d.line((16, y, 47, y), fill="#a98156")
        d.line((16, 55, 47, 55), fill=INK)
    else:
        d.rectangle((16, 36, 47, 55), fill="#b29468")
        for y in [40,48]: d.line((16,y,47,y),fill="#cfb584")
    for bit, edge in [(1,(16,4,47,4)), (2,(47,4,47,55)), (8,(16,4,16,55))]:
        if not mask & bit: d.line(edge, fill=INK, width=1)
    return image


def construction(mask: int) -> Image.Image:
    image = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(image)
    d.rectangle((17, 24, 46, 55), fill="#655542")
    for y in [29, 37, 45, 53]: d.line((19,y,44,y), fill=WOOD, width=2)
    for bit, x, y in [(1,18,24),(2,45,40),(4,18,54),(8,18,40)]:
        if not mask & bit:
            d.line((x,y,x,y-17),fill=INK,width=4)
            d.line((x,y,x,y-17),fill=LIGHT,width=2)
    if not mask & 4:
        d.line((18,38,45,38),fill=INK,width=4)
        d.line((18,39,45,53),fill=LIGHT,width=2)
        d.line((18,53,45,39),fill=LIGHT,width=2)
    d.rectangle((24,25,29,30),fill=SLATE,outline=INK)
    return image


def door(vertical: bool, part: str = "all") -> Image.Image:
    image = Image.new("RGBA", (64,64))
    d = ImageDraw.Draw(image)
    if vertical:
        for name, y in [("back",24),("front",55)]:
            if part not in ["all", name]: continue
            d.rectangle((16,y-23,47,y),fill=WOOD,outline=INK)
            d.rectangle((18,y-22,45,y-19),fill=LIGHT)
            for x in [19,43]: d.line((x,y-18,x,y-2),fill="#b38352")
    else:
        for x in [16,42]:
            d.rectangle((x,1,x+5,55),fill=WOOD,outline=INK)
            d.line((x+2,3,x+2,52),fill=LIGHT)
        d.rectangle((16,1,47,6),fill=SLATE,outline=INK)
    return image
