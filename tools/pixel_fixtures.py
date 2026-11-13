"""Axis-aligned temporary fixtures, authored on the square ground plane.

North is image up. Cardinal variants rotate the top view about its centre.
"""
from PIL import Image, ImageDraw

INK = "#202b3d"
WOOD = "#956443"
LIGHT = "#cfaa70"
CREAM = "#f1dfaf"
TEAL = "#438b78"
SLATE = "#7d989f"


def fixture(key: str) -> tuple[Image.Image, tuple[int, int]]:
    image = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(image)
    footprint = (1, 2) if key == "long_bed" else ((2, 1) if key in ["table", "workbench", "go_board"] else (1, 1))
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
        d.rectangle((30, 23, 34, 28), fill="#e6c665", outline=INK)
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
    elif key in ["stove", "furnace", "alchemy"]:
        d.rectangle((18, 18, 46, 46), fill="#8b8b83", outline=INK, width=2)
        for y in [25, 34, 42]:d.line((20, y, 44, y), fill="#58676d")
        d.ellipse((23, 21, 41, 39), fill=INK, outline=SLATE, width=2)
        d.ellipse((26, 24, 38, 36), fill="#5f856d" if key == "alchemy" else "#bd643e")
        d.rectangle((27, 18, 37, 22), fill=INK)
        if key == "stove":d.rectangle((29, 19, 34, 21), fill="#f0bd64")
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
        for x in [18,28,38]:
            d.rectangle((x,23,x+9,42),fill=WOOD,outline=INK)
            d.rectangle((x+2,25,x+7,39),fill=CREAM)
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


def wall(mask: int) -> Image.Image:
    """Opaque 32x32 coverage; neighbour bits remove internal border seams."""
    image = Image.new("RGBA", (64, 64))
    d = ImageDraw.Draw(image)
    d.rectangle((16,16,47,47),fill="#ac8654")
    for y in [19,27,35,43]:
        d.line((16,y,47,y),fill="#d1b37d",width=2)
        d.line((16,y+3,47,y+3),fill="#88613e")
    # Keep the border inside the occupied cell. A width=2 line centred on
    # x/y=47 would paint one extra pixel into the neighbouring tile.
    for bit, edge in [(1,(16,16,47,17)),(2,(46,16,47,47)),(4,(16,46,47,47)),(8,(16,16,17,47))]:
        if not mask & bit:d.rectangle(edge,fill=INK)
    return image


def door(vertical: bool) -> Image.Image:
    image = Image.new("RGBA", (64,64))
    d = ImageDraw.Draw(image)
    for x in [16,42]:
        d.rectangle((x,16,x+5,47),fill=WOOD,outline=INK)
        d.line((x+2,18,x+2,45),fill=LIGHT)
    d.rectangle((22,16,41,19),fill=SLATE,outline=INK)
    return image.transpose(Image.Transpose.ROTATE_90) if vertical else image
