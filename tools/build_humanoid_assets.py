"""Build the original eight-direction humanoid *technical sample*.

This is an offline, deterministic, small orthographic mesh rasterizer.  Its
native 96-pixel cells use hard coverage and three material shade levels, not
an antialiased miniature render or a half-resolution image enlarged again.
This retired sample is no longer read by the main scene or shipped. Current
assets are built by tools/build_art.py; this tool only reproduces old source art.  Positive local X is anatomical right,
positive Y is forwards, Z is up.  Neither pixels nor anatomy are mirrored.

Requires the already available Pillow 10-13.  Run from any working directory:
  python tools/build_humanoid_assets.py
  python tools/build_humanoid_assets.py --check
Previews and the machine-readable report belong in ignored logs/, not assets/.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
from typing import Callable, Iterable

from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "assets/characters/humanoid_sample"
MANIFEST = ROOT / "data/definitions/humanoid_appearance.json"
SIZE = 96
SS = 1
HI = SIZE * SS
ORIGIN = (48, 65)
SHADE_LEVELS = (.64, .82, 1.0)
# Retain the original sample's anchor visibility exactly.  Pixel coverage is
# native-resolution, while this metadata query keeps its original sample grid.
ANCHOR_SAMPLE_SCALE = 2
DIRECTIONS = ("N", "NE", "E", "SE", "S", "SW", "W", "NW")
# South is zero.  Anatomical right then projects to screen left.
HEADINGS = (math.pi, math.pi * .75, math.pi * .5, math.pi * .25,
            0.0, -math.pi * .25, -math.pi * .5, -math.pi * .75)
ACTIONS = {
    "idle": {"column": 0, "frames": 8, "cycle_ms": 1600},
    "walk": {"column": 8, "frames": 16, "cycle_ms": 900},
    "gesture": {"column": 24, "frames": 16, "cycle_ms": 1200},
}
LAYER_SPECS = (
    ("sword_far", "preview_sword", "none"),
    ("jade_far", "preview_jade", "none"),
    ("cape_far", "outer", "outer"),
    ("body", "base", "none"),
    ("robe", "body", "body"),
    ("detail", "body", "none"),
    ("cape_near", "outer", "outer"),
    ("jade_near", "preview_jade", "none"),
    ("sword_near", "preview_sword", "none"),
)
LAYER_ORDER = [item[0] for item in LAYER_SPECS]
V3 = tuple[float, float, float]
RGB = tuple[int, int, int]
Triangle = tuple[V3, V3, V3, RGB]
SKIN = (223, 201, 165)
INK = (36, 50, 55)
PAPER = (226, 219, 196)
GOLD = (226, 197, 129)
GREY = (239, 239, 239)
NEG_INF = -1.0e9


def add(a: V3, b: V3) -> V3:
    return a[0] + b[0], a[1] + b[1], a[2] + b[2]


def mul(a: V3, n: float) -> V3:
    return a[0] * n, a[1] * n, a[2] * n


def sub(a: V3, b: V3) -> V3:
    return a[0] - b[0], a[1] - b[1], a[2] - b[2]


def cross(a: V3, b: V3) -> V3:
    return a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]


def unit(a: V3) -> V3:
    length = math.sqrt(sum(value * value for value in a))
    return mul(a, 1.0 / length) if length > 1.0e-8 else (0., 0., 1.)


def rgb_scale(color: RGB, factor: float) -> RGB:
    return tuple(max(0, min(255, round(channel * factor))) for channel in color)  # type: ignore[return-value]


def rotate(point: V3, heading: float) -> V3:
    x, y, z = point
    return -x*math.cos(heading)+y*math.sin(heading), x*math.sin(heading)+y*math.cos(heading), z


def project(point: V3, heading: float) -> V3:
    x, y, z = rotate(point, heading)
    return ORIGIN[0] + x, ORIGIN[1] + .55*y - z, y + .55*z


def quad(out: list[Triangle], a: V3, b: V3, c: V3, d: V3, color: RGB) -> None:
    out.extend(((a, b, c, color), (a, c, d, color)))


def rings(out: list[Triangle], levels: Iterable[tuple[float, float, float, float, float]],
          color: RGB, segments: int = 16, start: float = 0., end: float = math.tau,
          striped: bool = False) -> None:
    """Levels are (z, radius_x, radius_y, offset_x, offset_y)."""
    levels = list(levels)
    for low, high in zip(levels, levels[1:]):
        for index in range(segments):
            a = start + (end-start) * index / segments
            b = start + (end-start) * (index+1) / segments
            def vertex(level: tuple[float, float, float, float, float], angle: float) -> V3:
                z, rx, ry, ox, oy = level
                return ox + rx*math.sin(angle), oy + ry*math.cos(angle), z
            tone = rgb_scale(color, 1.0 if not striped or index % 3 else .82)
            quad(out, vertex(low,a), vertex(low,b), vertex(high,b), vertex(high,a), tone)


def ellipsoid(out: list[Triangle], center: V3, radius: V3, color: RGB,
              material: Callable[[V3], RGB] | None = None,
              segments: int = 12, latitudes: int = 7) -> None:
    for latitude in range(latitudes):
        lo = -math.pi/2 + math.pi * latitude / latitudes
        hi = -math.pi/2 + math.pi * (latitude+1) / latitudes
        for longitude in range(segments):
            a, b = math.tau*longitude/segments, math.tau*(longitude+1)/segments
            def vertex(phi: float, theta: float) -> V3:
                return (center[0]+radius[0]*math.cos(phi)*math.sin(theta),
                        center[1]+radius[1]*math.cos(phi)*math.cos(theta),
                        center[2]+radius[2]*math.sin(phi))
            vertices = vertex(lo,a), vertex(lo,b), vertex(hi,b), vertex(hi,a)
            local_mid = (math.cos((lo+hi)/2)*math.sin((a+b)/2),
                         math.cos((lo+hi)/2)*math.cos((a+b)/2), math.sin((lo+hi)/2))
            tone = material(local_mid) if material else color
            quad(out, *vertices, tone)


def tube(out: list[Triangle], start: V3, end: V3, r_start: float, r_end: float,
         color: RGB, segments: int = 10) -> None:
    axis = unit(sub(end, start))
    other = (0., 0., 1.) if abs(axis[2]) < .9 else (0., 1., 0.)
    side = unit(cross(axis, other))
    vertical = unit(cross(axis, side))
    def vertex(base: V3, radius: float, angle: float) -> V3:
        return add(base, add(mul(side, radius*math.cos(angle)), mul(vertical, radius*math.sin(angle))))
    for i in range(segments):
        a, b = math.tau*i/segments, math.tau*(i+1)/segments
        quad(out, vertex(start,r_start,a), vertex(start,r_start,b),
             vertex(end,r_end,b), vertex(end,r_end,a), color)
        out.append((start, vertex(start,r_start,b), vertex(start,r_start,a), color))
        out.append((end, vertex(end,r_end,a), vertex(end,r_end,b), color))


def pose(action: str, phase: float) -> dict[str, V3 | float]:
    wave = math.sin(phase*math.tau)
    step = wave if action == "walk" else 0.
    breathe = .25*wave if action == "idle" else 0.
    lift = .55*(1-math.cos(phase*math.tau*2)) if action == "walk" else breathe
    # A short deliberate left-hand demonstration, not an implemented attack.
    gesture = math.sin(math.pi*phase)**2 if action == "gesture" else 0.
    left = (-10.+5.5*gesture, 1.+7.*gesture+2.2*step, 17.+12.*gesture+lift)
    right = (10., 1.-2.2*step, 17.+lift)
    return {
        "lift": lift, "step": step, "gesture": gesture,
        "left_hand": left, "right_hand": right,
        "left_waist": (-6.1, .1, 15.+lift),
        "right_waist": (6.1, .1, 15.+lift),
        "head": (0., 0., 39.+lift), "back": (0., -3.6, 24.+lift),
    }


def make_meshes(action: str, phase: float) -> tuple[dict[str, list[Triangle]], dict[str, V3 | float]]:
    p = pose(action, phase)
    lift, step, gesture = float(p["lift"]), float(p["step"]), float(p["gesture"])
    groups: dict[str, list[Triangle]] = {name: [] for name in ("body", "robe", "detail", "cape", "sword", "jade")}
    body, robe, detail, cape, sword, jade = (groups[name] for name in groups)
    for sign in (-1., 1.):
        stride = sign*step*3.8
        foot_lift = max(0., -sign*step)*1.5 if action == "walk" else 0.
        ellipsoid(body, (sign*3.6,stride,2.5+foot_lift), (2.4,3.4,2.5), INK, segments=10,latitudes=5)
        tube(body,(sign*3.4,0.,12.+lift),(sign*3.6,stride,4.+foot_lift),2.2,1.8,(103,109,108))
    rings(body, ((9.+lift,4.6,2.5,0.,0.),(20.+lift,5.2,2.8,0.,0.),
                 (26.+lift,5.8,2.6,0.,0.)), (131,139,132))
    tube(body,(0.,0.,25.+lift),(0.,0.,30.+lift),1.9,1.8,SKIN)
    rings(robe, ((7.+lift,8.2,4.6,0.,.25*step),(15.+lift,5.8,3.3,0.,0.),
                 (24.5+lift,7.,3.5,0.,0.),(26.+lift,5.2,2.7,0.,0.)), GREY)
    for name, sign in (("left_hand",-1.),("right_hand",1.)):
        hand = p[name]
        assert isinstance(hand, tuple)
        shoulder = (sign*5.6,0.,24.5+lift)
        elbow = (sign*8.1,hand[1]*.6,21.+lift+(gesture*4. if sign<0 else 0.))
        tube(body, shoulder, hand,1.5,1.35,SKIN)
        tube(robe,shoulder,elbow,2.9,2.7,GREY)
        cuff = add(hand,mul(unit(sub(elbow,hand)),1.5))
        tube(robe,elbow,cuff,2.7,2.2,GREY)
        ellipsoid(body,hand,(1.7,1.7,2.),SKIN,segments=10,latitudes=5)
    # The front collar belongs to the robe, the back is unadorned.
    quad(detail,(-4.9,2.6,25.3+lift),(-3.8,3.1,25.8+lift),
         (3.1,3.5,18.2+lift),(1.9,3.55,17.9+lift),PAPER)
    quad(detail,(4.9,2.6,25.3+lift),(3.8,3.1,25.8+lift),
         (-2.3,3.6,19.8+lift),(-1.2,3.7,19.3+lift),(108,120,113))
    rings(detail,((14.4+lift,6.05,3.55,0.,0.),(16.5+lift,6.05,3.55,0.,0.)),INK)
    # A small, neutral belt clasp.  It is not the right-hip jade accessory.
    ellipsoid(detail,(.6,3.65,15.5+lift),(.9,.4,.75),GOLD,segments=8,latitudes=4)
    head_center = (0.,0.,34.6+lift)
    def head_material(normal: V3) -> RGB:
        return INK if normal[2]>.42 or (normal[1]<-.15 and normal[2]>-.8) else SKIN
    ellipsoid(body,head_center,(5.25,4.65,6.2),SKIN,head_material,segments=18,latitudes=10)
    ellipsoid(body,(0.,-1.,42.+lift),(2.6,2.5,2.6),INK,segments=12,latitudes=6)
    tube(body,(-3.,-1.,41.2+lift),(3.,-1.,41.2+lift),.38,.38,GOLD,segments=6)
    for x in (-1.9,1.9):
        ellipsoid(body,(x,4.35,35.+lift),(.45,.4,.52),INK,segments=8,latitudes=4)
    ellipsoid(body,(0.,4.8,33.6+lift),(.75,.9,.9),SKIN,segments=8,latitudes=5)
    # Open-front straw rain cape: back and lateral panels, not a mirrored poncho.
    # Each narrow sector is a straw bundle.  The upper opening clears the head.
    for i in range(30):
        start = math.radians(56.+248.*i/30.)
        end = math.radians(56.+248.*(i+1)/30.)
        sway = .55*step*math.sin((start+end)/2)
        tone = (242,242,242) if i%3 else (196,196,196)
        rings(cape,((8.5+lift,12.2,6.7,0.,-1.+sway),
                    (18.+lift,10.2,5.3,0.,-.8),
                    (26.+lift,7.6,3.9,0.,-.5)),tone,segments=1,start=start,end=end)
    # Collar and shoulder ties are also tintable straw.
    rings(cape,((24.8+lift,7.7,4.0,0.,-.5),(26.3+lift,7.7,4.0,0.,-.5)),
          (188,188,188),segments=20,start=math.radians(56),end=math.radians(304))
    hand = p["left_hand"]
    assert isinstance(hand, tuple)
    axis = unit((-.1+1.04*gesture,.7-.47*gesture,.65-.15*gesture))
    # Blade is a narrow diamond prism, with the tang through the real left hand.
    start = add(hand,mul(axis,1.2))
    base = add(start,mul(axis,2.3))
    tip = add(base,mul(axis,20.))
    side = unit(cross(axis,(0.,0.,1.)))
    normal = unit(cross(axis,side))
    tube(sword,add(hand,mul(axis,-2.6)),start,.7,.7,(91,77,60),segments=8)
    tube(sword,add(start,mul(side,-3.)),add(start,mul(side,3.)),.6,.6,GOLD,segments=8)
    left,right = add(base,mul(side,-1.25)),add(base,mul(side,1.25))
    ridge_a,ridge_b = add(base,mul(normal,.5)),add(base,mul(normal,-.5))
    sword.extend(((left,ridge_a,tip,(228,239,231)),(ridge_a,right,tip,(171,197,196)),
                  (right,ridge_b,tip,(114,147,151)),(ridge_b,left,tip,(196,219,217))))
    # The right-hip cord remains attached to the anatomical waist, not screen right.
    waist = p["right_waist"]
    assert isinstance(waist, tuple)
    pendant = (12.8,1.8+.45*step,10.2+lift+.3*math.sin(phase*math.tau))
    tube(jade,waist,add(pendant,(0.,0.,2.0)),.24,.22,(156,118,64),segments=6)
    ellipsoid(jade,pendant,(1.7,.85,2.1),(91,194,151),segments=12,latitudes=7)
    ellipsoid(jade,add(pendant,(0.,.8,.4)),(.55,.22,.55),(200,234,197),segments=8,latitudes=4)
    return groups,p


def raster(mesh: list[Triangle], heading: float) -> tuple[Image.Image,list[float]]:
    colors = [(0,0,0,0)]*(HI*HI)
    depths = [NEG_INF]*(HI*HI)
    view = unit((0.,1.,.55))
    light = unit((-.5,.65,1.))
    for a,b,c,color in mesh:
        aa,bb,cc = project(a,heading),project(b,heading),project(c,heading)
        ax,ay = aa[0]*SS,aa[1]*SS
        bx,by = bb[0]*SS,bb[1]*SS
        cx,cy = cc[0]*SS,cc[1]*SS
        det = (by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
        if abs(det)<1.e-7:
            continue
        normal = unit(cross(sub(rotate(b,heading),rotate(a,heading)),
                            sub(rotate(c,heading),rotate(a,heading))))
        facing = sum(x*y for x,y in zip(normal,view))
        if facing<0:
            normal=mul(normal,-1.)
        brightness = .69+.29*max(0.,sum(x*y for x,y in zip(normal,light)))
        if abs(facing)<.18:
            brightness*=.78
        brightness = min(SHADE_LEVELS, key=lambda level: abs(level-brightness))
        rgba = (*rgb_scale(color,brightness),255)
        x0,x1 = max(0,math.floor(min(ax,bx,cx))),min(HI-1,math.ceil(max(ax,bx,cx)))
        y0,y1 = max(0,math.floor(min(ay,by,cy))),min(HI-1,math.ceil(max(ay,by,cy)))
        inv = 1./det
        for y in range(y0,y1+1):
            py=y+.5
            for x in range(x0,x1+1):
                px=x+.5
                u=((by-cy)*(px-cx)+(cx-bx)*(py-cy))*inv
                v=((cy-ay)*(px-cx)+(ax-cx)*(py-cy))*inv
                w=1.-u-v
                if u<-.00001 or v<-.00001 or w<-.00001:
                    continue
                z=u*aa[2]+v*bb[2]+w*cc[2]
                idx=y*HI+x
                if z>depths[idx]:
                    depths[idx]=z
                    colors[idx]=rgba
    image=Image.new("RGBA",(HI,HI))
    image.putdata(colors)
    return image,depths


def anchor_surface_depth(mesh: list[Triangle], heading: float, x: float, y: float) -> float:
    """Query the former 2x grid only for stable legacy attachment metadata.

    Body/robe/detail clipping never changes the greatest of their depths, so
    their raw nearest surface gives the same visibility reference without
    rasterizing another image or antialiasing any output pixel.
    """
    scale = ANCHOR_SAMPLE_SCALE
    maximum = SIZE*scale-1
    px = min(maximum,max(0,int(x*scale)))+.5
    py = min(maximum,max(0,int(y*scale)))+.5
    depth = NEG_INF
    for a,b,c,_color in mesh:
        aa,bb,cc = project(a,heading),project(b,heading),project(c,heading)
        ax,ay = aa[0]*scale,aa[1]*scale
        bx,by = bb[0]*scale,bb[1]*scale
        cx,cy = cc[0]*scale,cc[1]*scale
        if px<min(ax,bx,cx)-.5 or px>max(ax,bx,cx)+.5 or py<min(ay,by,cy)-.5 or py>max(ay,by,cy)+.5:
            continue
        det = (by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
        if abs(det)<1.e-7:
            continue
        inv = 1./det
        u = ((by-cy)*(px-cx)+(cx-bx)*(py-cy))*inv
        v = ((cy-ay)*(px-cx)+(ax-cx)*(py-cy))*inv
        w = 1.-u-v
        if u>=-.00001 and v>=-.00001 and w>=-.00001:
            depth = max(depth,u*aa[2]+v*bb[2]+w*cc[2])
    return depth


def keep_in_front(image: Image.Image, depth: list[float], reference: list[float]) -> None:
    pixels=list(flat_pixels(image))
    for i,z in enumerate(depth):
        if z<reference[i]-.08:
            pixels[i]=(0,0,0,0)
            depth[i]=NEG_INF
    image.putdata(pixels)


def split_layers(image: Image.Image, depth: list[float], reference: list[float]) -> tuple[Image.Image,Image.Image]:
    far=[(0,0,0,0)]*(HI*HI)
    near=far.copy()
    for i,rgba in enumerate(flat_pixels(image)):
        if not rgba[3]:
            continue
        ref=reference[i]
        if ref==NEG_INF:
            # Compare to the anatomical middle plane if outside the silhouette.
            ref=.55*(ORIGIN[1]-(i//HI+.5)/SS)
        (far if depth[i]<ref-.08 else near)[i]=rgba
    images=[]
    for pixels in (far,near):
        part=Image.new("RGBA",(HI,HI))
        part.putdata(pixels)
        images.append(part)
    return images[0],images[1]


def flat_pixels(image: Image.Image) -> Iterable[tuple[int,int,int,int]]:
    # Pillow 12.1 renamed getdata; retain compatibility with the documented
    # preinstalled 10-13 range without emitting a deprecation on newer Pillow.
    method=getattr(image,"get_flattened_data",None)
    return method() if method else image.getdata()


def render_frame(action: str,phase: float,heading: float) -> tuple[dict[str,Image.Image],dict]:
    groups,p=make_meshes(action,phase)
    raw={key:raster(mesh,heading) for key,mesh in groups.items()}
    body,body_z=raw["body"]
    robe,robe_z=raw["robe"]
    keep_in_front(robe,robe_z,body_z)
    main_z=[max(a,b) for a,b in zip(body_z,robe_z)]
    detail,detail_z=raw["detail"]
    keep_in_front(detail,detail_z,main_z)
    main_z=[max(a,b) for a,b in zip(main_z,detail_z)]
    layers={"body":body,"robe":robe,"detail":detail}
    for name in ("cape","sword","jade"):
        layers[name+"_far"],layers[name+"_near"]=split_layers(*raw[name],main_z)
    anchors={}
    anchor_surface=groups["body"]+groups["robe"]+groups["detail"]
    for name in ("left_hand","right_hand","left_waist","right_waist","head","back"):
        point=p[name]
        assert isinstance(point,tuple)
        x,y,depth=project(point,heading)
        target=project(add(point,(0.,1.,0.)),heading)
        anchors[name]={"position":[round(x,3),round(y,3)],
                       "angle_deg":round(math.degrees(math.atan2(target[1]-y,target[0]-x)),3),
                       "visible":depth>=anchor_surface_depth(anchor_surface,heading,x,y)-1.5,"depth":round(depth,3)}
    return layers,anchors


def png_bytes(image: Image.Image) -> bytes:
    buffer=io.BytesIO()
    image.save(buffer,format="PNG",compress_level=9)
    return buffer.getvalue()


def tint(image: Image.Image,color: str) -> Image.Image:
    # Modulate RGB only; retain the hard alpha exactly once.
    rgb=ImageChops.multiply(image.convert("RGB"),Image.new("RGB",image.size,color))
    rgb.putalpha(image.getchannel("A"))
    return rgb


def composite(frame: dict[str,Image.Image],outer: bool=True,accessories: bool=True) -> Image.Image:
    result=Image.new("RGBA",(SIZE,SIZE))
    for key,slot,color in LAYER_SPECS:
        if (slot=="outer" and not outer) or (slot.startswith("preview_") and not accessories):
            continue
        image=frame[key]
        if color=="body":
            image=tint(image,"#79947e")
        elif color=="outer":
            image=tint(image,"#b5a16a")
        result.alpha_composite(image)
    return result


def checker(size: tuple[int,int]) -> Image.Image:
    image=Image.new("RGBA",size,(47,63,62,255))
    draw=ImageDraw.Draw(image)
    for y in range(0,size[1],12):
        for x in range(0,size[0],12):
            if (x//12+y//12)%2:
                draw.rectangle((x,y,x+11,y+11),fill=(54,72,69,255))
    return image


def save_previews(frames: dict,report: dict) -> None:
    log_dir=ROOT/"logs"
    log_dir.mkdir(exist_ok=True)
    keys=[(action,index) for action in ACTIONS for index in range(0,ACTIONS[action]["frames"],ACTIONS[action]["frames"]//4)]
    for outer,label in ((False,"plain"),(True,"cape")):
        sheet=checker((48+len(keys)*SIZE,32+8*(SIZE+16)))
        draw=ImageDraw.Draw(sheet)
        for column,(action,index) in enumerate(keys):
            draw.text((50+column*SIZE,9),f"{action} {index:02}",fill=(238,228,203,255))
        for row,direction in enumerate(DIRECTIONS):
            y=32+row*(SIZE+16)
            draw.text((6,y+38),direction,fill=(238,228,203,255))
            for column,(action,index) in enumerate(keys):
                sheet.alpha_composite(composite(frames[direction][action][index],outer),
                                      (48+column*SIZE,y))
        sheet.convert("RGB").save(log_dir/f"humanoid_sample_{label}_contact.png")
    # A native-scale moving family and a 2x nearest view share exactly the same frames.
    for action in ACTIONS:
        animation=[]
        for index in range(ACTIONS[action]["frames"]):
            strip=checker((8*SIZE,SIZE+20))
            draw=ImageDraw.Draw(strip)
            for direction_index,direction in enumerate(DIRECTIONS):
                strip.alpha_composite(composite(frames[direction][action][index]),(direction_index*SIZE,20))
                draw.text((direction_index*SIZE+40,3),direction,fill=(238,228,203,255))
            animation.append(strip.resize((16*SIZE,(SIZE+20)*2),Image.Resampling.NEAREST).convert("RGB"))
        animation[0].save(log_dir/f"humanoid_sample_{action}.gif",save_all=True,
                          append_images=animation[1:],duration=round(ACTIONS[action]["cycle_ms"]/ACTIONS[action]["frames"]),
                          loop=0,disposal=2)
    (log_dir/"humanoid_sample_asset_report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")


def build(check: bool,previews: bool) -> int:
    atlases={key:Image.new("RGBA",(3840,768)) for key in LAYER_ORDER}
    manifest={
        "schema_version":1,"id":"humanoid_sample","status":"original_technical_sample",
        "frame_size":[SIZE,SIZE],"atlas_size":[3840,768],"origin":list(ORIGIN),
        "directions":list(DIRECTIONS),"actions":ACTIONS,"turn_hysteresis_degrees":5.0,
        "anatomy":{"positive_local_x":"right","positive_local_y":"forward","positive_local_z":"up",
                   "screen_north":[0,-1],"mirror_policy":"none"},
        "layers":[{"id":key,"texture":f"res://assets/characters/humanoid_sample/spr_{key}.png",
                   "slot":slot,"tint":color} for key,slot,color in LAYER_SPECS],
        "preview_accessories":{"sword":"left_hand","jade":"right_waist",
                               "grants_items":False,"grants_combat_effects":False},
        "frames":{},
    }
    preview_frames={}
    clipped=[]
    unique_directions=[]
    for row,(direction,heading) in enumerate(zip(DIRECTIONS,HEADINGS)):
        print(f"Rasterizing {direction}: 40 independent frames",flush=True)
        manifest["frames"][direction]={}
        preview_frames[direction]={}
        for action,spec in ACTIONS.items():
            metadata=[]
            preview_frames[direction][action]=[]
            for index in range(spec["frames"]):
                frame,anchors=render_frame(action,index/spec["frames"],heading)
                rect=[(spec["column"]+index)*SIZE,row*SIZE,SIZE,SIZE]
                for key,image in frame.items():
                    atlases[key].paste(image,(rect[0],rect[1]))
                    box=image.getchannel("A").getbbox()
                    if box and (box[0]==0 or box[1]==0 or box[2]==SIZE or box[3]==SIZE):
                        clipped.append([direction,action,index,key,box])
                metadata.append({"rect":rect,"origin":list(ORIGIN),"anchors":anchors,
                                 "layer_order":LAYER_ORDER})
                preview_frames[direction][action].append(frame)
            manifest["frames"][direction][action]=metadata
        unique_directions.append(hashlib.sha256(composite(preview_frames[direction]["idle"][0]).tobytes()).hexdigest())
    if clipped:
        raise ValueError(f"Clipped source frames: {clipped[:8]}")
    if len(set(unique_directions))!=8:
        raise ValueError("The eight independently rendered directions are not unique")
    outputs={ASSET_DIR/f"spr_{key}.png":png_bytes(image) for key,image in atlases.items()}
    outputs[MANIFEST]=(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n").encode("utf-8")
    report={"directions":8,"frames_per_direction":40,"total_frames":320,"layers":9,
            "frame_size":[96,96],"atlas_size":[3840,768],"origin":list(ORIGIN),
            "presentation":"native_pixel_placeholder","raster_size":[HI,HI],
            "shade_levels":list(SHADE_LEVELS),"alpha_policy":"binary_no_antialiasing",
            "clipped_frames":clipped,"unique_direction_composites":len(set(unique_directions)),
            "decoded_rgba_mib":round(3840*768*4*9/1024/1024,3),"files":[]}
    mismatches=[]
    for path,content in outputs.items():
        if check:
            if not path.is_file() or path.read_bytes()!=content:
                mismatches.append(str(path.relative_to(ROOT)))
        else:
            path.parent.mkdir(parents=True,exist_ok=True)
            path.write_bytes(content)
        record={"path":str(path.relative_to(ROOT)).replace("\\","/"),"bytes":len(content),
                "sha256":hashlib.sha256(content).hexdigest()}
        if path.suffix==".png":
            image=atlases[path.stem.removeprefix("spr_")]
            alpha=image.getchannel("A")
            if alpha.getextrema()!=(0,255):
                raise ValueError(f"Missing usable transparent/opaque alpha: {path}")
            if any(count and value not in (0,255) for value,count in enumerate(alpha.histogram())):
                raise ValueError(f"Pixel placeholder must not contain soft alpha: {path}")
            colors=image.getcolors(SIZE*SIZE*40*8)
            if colors is None or len(colors)>64:
                raise ValueError(f"Pixel placeholder exceeds 64 layer colors: {path}")
            record["mode"]=image.mode
            record["alpha_extrema"]=list(alpha.getextrema())
            record["color_count"]=len(colors)
        report["files"].append(record)
    if previews:
        save_previews(preview_frames,report)
    if mismatches:
        print("FAIL: generated files differ: "+", ".join(mismatches))
        return 1
    print(f"PASS: {'checked' if check else 'wrote'} {len(outputs)} deterministic files; "
          "320 frames, 8 unique directions, 9 layers, no clipped alpha, stable [48,65] origin; "
          "native 96px hard pixels, binary alpha, <=64 colors/layer; "
          f"decoded RGBA {report['decoded_rgba_mib']} MiB")
    return 0


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check",action="store_true",help="regenerate in memory and fail on any byte difference")
    parser.add_argument("--no-previews",action="store_true",help="do not write ignored logs previews/report")
    arguments=parser.parse_args()
    raise SystemExit(build(arguments.check,not arguments.no_previews))
