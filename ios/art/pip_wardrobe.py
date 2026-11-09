# Pip's chest wardrobe: draws the new pieces as shape layers inside the nine Lottie animations (hidden, like the
# pieces made in After Effects: the app shows one by setting its layer's opacity) and renders the small head pictures
# with each head or face piece, lined up with the existing ones.
#
#   python -X utf8 -I ios/art/pip_wardrobe.py ios            writes the animations and the head pictures
#   python -X utf8 -I ios/art/pip_wardrobe.py ios preview D  only draws contact sheets into folder D
#
# Running it again replaces what it made before. Coordinates are the base pose's, as in add_accessories.jsx.
import copy, glob, json, math, os, sys
from PIL import Image, ImageDraw

C = dict(
    ink=(0.17, 0.12, 0.18), white=(1, 1, 1), mint=(0.2, 0.88, 0.71), mintDark=(0.07, 0.64, 0.61),
    red=(0.9, 0.29, 0.31), redDark=(0.72, 0.18, 0.22), blue=(0.24, 0.38, 0.78), blueDark=(0.16, 0.26, 0.58),
    gold=(0.98, 0.78, 0.25), goldDark=(0.85, 0.6, 0.12), leaf=(0.47, 0.8, 0.39), leafDark=(0.31, 0.65, 0.3),
    cream=(1, 0.95, 0.88), pink=(1, 0.55, 0.6), pinkDark=(0.9, 0.36, 0.5), grey=(0.2, 0.22, 0.28), greyLight=(0.36, 0.39, 0.47),
    silver=(0.78, 0.81, 0.86), purple=(0.5, 0.36, 0.86), purpleDark=(0.35, 0.22, 0.66), brown=(0.55, 0.36, 0.2),
    brownDark=(0.4, 0.25, 0.13), cyan=(0.3, 0.85, 1), sky=(0.55, 0.75, 1), pearl=(0.97, 0.95, 0.92), orange=(1, 0.62, 0.2),
)

# ---- a tiny drawing language: a piece is a list of groups, bottom first ----

def el(cx, cy, w, h=None): return ("el", cx, cy, w, h if h is not None else w)
def rc(cx, cy, w, h, r=0): return ("rc", cx, cy, w, h, r)
def poly(pts, closed=True): return ("sh", [list(p) for p in pts], [[0, 0]] * len(pts), [[0, 0]] * len(pts), closed)
def curve(pts, ins, outs, closed=False): return ("sh", [list(p) for p in pts], [list(p) for p in ins], [list(p) for p in outs], closed)
def line(a, b): return poly([a, b], closed=False)

def arc3(a, top, b, pull):
    """A soft arc through three points: `pull` is how far the top's handles reach sideways"""
    return curve([a, top, b], [[0, 0], [-pull, 0], [0, 0]], [[0, 0], [pull, 0], [0, 0]])

def dome(cx, base, rx, ry):
    k = 0.5523
    return curve([[cx - rx, base], [cx, base - ry], [cx + rx, base]], [[0, 0], [-k * rx, 0], [0, -k * ry]], [[0, -k * ry], [k * rx, 0], [0, 0]], closed=True)

def star(cx, cy, r, points=5, inner=0.45, turn=-90):
    pts = []
    for i in range(points * 2):
        a = math.radians(turn + i * 180 / points)
        rr = r if i % 2 == 0 else r * inner
        pts.append([round(cx + rr * math.cos(a), 2), round(cy + rr * math.sin(a), 2)])
    return poly(pts)

def G(name, items, fill=None, stroke=None, rot=None, fo=100, so=100):
    """fill: colour name; stroke: (colour name, width); rot: (cx, cy, degrees)"""
    return dict(name=name, items=items, fill=(C[fill], fo) if fill else None, stroke=(C[stroke[0]], stroke[1], so) if stroke else None, rot=rot)

def mirror_item(it):
    if it[0] in ("el", "rc"): return (it[0], 1000 - it[1]) + tuple(it[2:])
    _, v, i, o, closed = it
    return ("sh", [[1000 - x, y] for x, y in v], [[-x, y] for x, y in i], [[-x, y] for x, y in o], closed)

def both(items): return items + [mirror_item(i) for i in items]

def mirrored(g, name):
    m = dict(g, name=name, items=[mirror_item(i) for i in g["items"]])
    if g["rot"]: m["rot"] = (1000 - g["rot"][0], g["rot"][1], -g["rot"][2])
    return m

def heart(cx, cy, s): return [el(cx - 0.25 * s, cy - 0.16 * s, 0.56 * s), el(cx + 0.25 * s, cy - 0.16 * s, 0.56 * s), poly([[cx - 0.5 * s, cy - 0.02 * s], [cx + 0.5 * s, cy - 0.02 * s], [cx, cy + 0.5 * s]])]

def necklace(n, r=130, drop=70, cy=622):
    return [(500 + r * math.cos(math.radians(180 - i * 180 / (n - 1))), cy + drop * math.sin(math.radians(i * 180 / (n - 1)))) for i in range(n)]

def pieces():
    P = []
    def add(id, layer, slot, groups): P.append(dict(id=id, layer="Acc " + layer, slot=slot, groups=groups))

    # ---------- head ----------
    add("party-hat", "Party hat", "head", [
        G("cone", [poly([[340, 290], [404, 130], [468, 290]])], fill="red", rot=(404, 290, -16)),
        G("stripes", [line([363, 232], [445, 232]), line([383, 182], [425, 182])], stroke=("gold", 14), rot=(404, 290, -16)),
        G("brim", [rc(404, 288, 142, 24, 12)], fill="gold", rot=(404, 290, -16)),
        G("pompom", [el(404, 128, 40)], fill="mint", rot=(404, 290, -16))])
    add("beanie", "Beanie", "head", [
        G("dome", [dome(500, 300, 152, 138)], fill="blue"),
        G("ribs", [line([450, 190], [444, 262]), line([500, 172], [500, 256]), line([550, 190], [556, 262])], stroke=("blueDark", 7), so=70),
        G("fold", [arc3([350, 306], [500, 264], [650, 306], 96)], stroke=("blueDark", 46)),
        G("pompom", [el(500, 160, 54)], fill="cream")])
    add("cap", "Cap", "head", [
        G("visor", [el(604, 286, 200, 46)], fill="redDark", rot=(604, 286, 9)),
        G("dome", [dome(500, 292, 146, 116)], fill="red"),
        G("panel", [curve([[500, 178], [500, 290]], [[0, 0], [-34, -50]], [[-34, 50], [0, 0]])], stroke=("redDark", 6), so=70),
        G("button", [el(500, 178, 20)], fill="white")])
    add("flower", "Flower", "head", [
        G("petals", [el(650 + 25 * math.cos(math.radians(a)), 318 + 25 * math.sin(math.radians(a)), 38) for a in range(-90, 270, 72)], fill="pink"),
        G("leaf", [el(612, 350, 44, 20)], fill="leaf", rot=(612, 350, -35)),
        G("middle", [el(650, 318, 28)], fill="gold")])
    add("head-bow", "Head bow", "head", [
        G("wings", [poly([[366, 300], [306, 262], [306, 338]]), poly([[366, 300], [426, 262], [426, 338]])], fill="pink", rot=(366, 300, -18)),
        G("knot", [rc(366, 300, 30, 36, 11)], fill="pinkDark", rot=(366, 300, -18))])
    add("top-hat", "Top hat", "head", [
        G("crown", [rc(500, 190, 150, 150, 12)], fill="ink"),
        G("band", [rc(500, 240, 150, 26, 0)], fill="red"),
        G("brim", [rc(500, 266, 250, 28, 14)], fill="ink"),
        G("shine", [line([448, 136], [448, 214])], stroke=("white", 8), so=22)])
    add("chef-hat", "Chef hat", "head", [
        G("puff", [el(440, 186, 104), el(560, 186, 104), el(500, 160, 124)], fill="white"),
        G("folds", [line([470, 196], [470, 236]), line([530, 196], [530, 236])], stroke=("silver", 6)),
        G("band", [rc(500, 252, 168, 56, 8)], fill="white", stroke=("silver", 5))])
    add("cowboy", "Cowboy hat", "head", [
        G("brim", [el(500, 270, 360, 70)], fill="brownDark"),
        G("crown", [curve([[416, 268], [430, 170], [500, 190], [570, 170], [584, 268]], [[0, 0], [-10, 20], [-24, 0], [-26, -22], [0, 0]], [[0, 0], [26, -22], [24, 0], [10, 20], [0, 0]], closed=True)], fill="brown"),
        G("band", [rc(500, 252, 166, 20, 4)], fill="ink"),
        G("star", [star(500, 252, 13)], fill="gold")])
    add("grad-cap", "Grad cap", "head", [
        G("skull", [rc(500, 256, 160, 56, 16)], fill="ink"),
        G("board", [poly([[352, 214], [500, 166], [648, 214], [500, 262]])], fill="grey"),
        G("cord", [curve([[500, 214], [616, 236], [620, 290]], [[0, 0], [-30, -8], [0, -20]], [[30, 8], [4, 18], [0, 0]])], stroke=("gold", 7)),
        G("tassel", [rc(620, 300, 18, 34, 7)], fill="gold"),
        G("button", [el(500, 214, 18)], fill="gold")])
    add("santa", "Santa hat", "head", [
        G("cone", [curve([[398, 284], [520, 122], [640, 214], [602, 284]], [[0, 0], [-50, 20], [-20, -50], [0, 0]], [[20, -80], [60, -10], [0, 0], [0, 0]], closed=True)], fill="red"),
        G("fur", [rc(500, 282, 236, 46, 23)], fill="white"),
        G("pompom", [el(640, 222, 50)], fill="white")])
    add("pirate", "Pirate hat", "head", [
        G("hat", [curve([[322, 282], [372, 176], [500, 138], [628, 176], [678, 282]], [[0, 0], [-30, 40], [-50, 0], [-40, -30], [0, 0]], [[0, 0], [40, -30], [50, 0], [30, 40], [0, 0]], closed=True)], fill="ink"),
        G("trim", [curve([[330, 276], [500, 250], [670, 276]], [[0, 0], [-60, 0], [0, 0]], [[0, 0], [60, 0], [0, 0]])], stroke=("gold", 9)),
        G("bones", [line([470, 190], [530, 236]), line([530, 190], [470, 236])], stroke=("white", 9)),
        G("skull", [el(500, 206, 46, 42), rc(500, 228, 24, 16, 5)], fill="white"),
        G("eyes", [el(491, 204, 9), el(509, 204, 9)], fill="ink")])
    add("wizard", "Wizard hat", "head", [
        G("cone", [curve([[392, 284], [470, 150], [560, 66], [608, 284]], [[0, 0], [-20, 40], [-40, 30], [0, 0]], [[20, -50], [20, -40], [10, 60], [0, 0]], closed=True)], fill="purple"),
        G("brim", [el(500, 284, 320, 58)], fill="purpleDark"),
        G("band", [arc3([404, 262], [500, 248], [600, 262], 50)], stroke=("gold", 14)),
        G("stars", [star(472, 196, 16), star(540, 150, 11), star(538, 222, 9)], fill="gold")])
    viking_horn = G("horn L", [curve([[372, 262], [300, 206], [296, 112], [392, 216]], [[0, 0], [20, 30], [-10, 40], [-40, -20]], [[-30, -6], [-10, -34], [30, 20], [0, 0]], closed=True)], fill="cream")
    add("viking", "Viking helmet", "head", [
        viking_horn, mirrored(viking_horn, "horn R"),
        G("dome", [dome(500, 296, 150, 124)], fill="silver"),
        G("ridge", [line([500, 174], [500, 290])], stroke=("greyLight", 16)),
        G("rim", [arc3([352, 300], [500, 262], [648, 300], 96)], stroke=("greyLight", 30)),
        G("rivets", [el(420, 284, 13), el(500, 270, 13), el(580, 284, 13)], fill="gold")])
    add("crown", "Crown", "head", [
        G("velvet", [el(500, 226, 176, 116)], fill="redDark"),
        G("spikes", [poly([[404, 262], [396, 168], [450, 218], [500, 142], [550, 218], [604, 168], [596, 262]])], fill="gold", stroke=("goldDark", 6)),
        G("base", [rc(500, 266, 204, 36, 9)], fill="gold", stroke=("goldDark", 6)),
        G("tips", [el(396, 166, 20), el(500, 140, 22), el(604, 166, 20)], fill="gold", stroke=("goldDark", 5)),
        G("ruby", [el(500, 266, 22)], fill="red"),
        G("gems", [el(446, 266, 15), el(554, 266, 15)], fill="mint")])
    add("halo", "Halo", "head", [
        G("glow", [el(500, 150, 210, 60)], stroke=("gold", 34), so=28),
        G("ring", [el(500, 150, 210, 60)], stroke=("gold", 15))])

    # ---------- face ----------
    add("heart-glasses", "Heart glasses", "face", [
        G("temples", both([line([362, 440], [304, 428])]), stroke=("redDark", 9)),
        G("bridge", [curve([[474, 440], [526, 440]], [[0, 0], [-10, -12]], [[10, -12], [0, 0]])], stroke=("redDark", 9)),
        G("frames", heart(420, 452, 128) + heart(580, 452, 128), fill="redDark"),
        G("lenses", heart(420, 452, 100) + heart(580, 452, 100), fill="pink"),
        G("shine", [line([392, 428], [404, 420]), line([552, 428], [564, 420])], stroke=("white", 8), so=80)])
    add("monocle", "Monocle", "face", [
        G("chain", [curve([[628, 490], [660, 600]], [[0, 0], [-40, -40]], [[50, 30], [0, 0]])], stroke=("gold", 5)),
        G("lens", [el(580, 452, 116)], fill="white", fo=16, stroke=("gold", 10)),
        G("shine", [line([556, 430], [572, 420])], stroke=("white", 7), so=80)])
    add("eye-patch", "Eye patch", "face", [
        G("strap", [line([296, 414], [704, 384])], stroke=("ink", 10)),
        G("patch", [curve([[364, 430], [476, 420], [468, 470], [420, 506], [372, 474]], [[0, 0], [0, 0], [10, -10], [20, 0], [-4, 16]], [[0, 0], [0, 0], [-6, 24], [-22, 0], [-10, -12]], closed=True)], fill="ink")])
    stache = G("left", [curve([[500, 532], [446, 520], [386, 552], [440, 566], [500, 550]], [[0, 0], [20, -8], [16, 6], [-26, 6], [-20, 12]], [[-20, -14], [-26, 10], [10, 18], [24, -6], [0, 0]], closed=True)], fill="ink")
    add("mustache", "Mustache", "face", [stache, mirrored(stache, "right")])
    add("clown-nose", "Clown nose", "face", [
        G("nose", [el(500, 512, 70)], fill="red"),
        G("shine", [el(487, 499, 18)], fill="white", fo=75)])
    add("ski-goggles", "Ski goggles", "face", [
        G("strap", [line([294, 446], [706, 446])], stroke=("purpleDark", 34)),
        G("frame", [rc(500, 450, 336, 124, 56)], fill="grey"),
        G("lens", [rc(500, 450, 300, 90, 42)], fill="orange"),
        G("tint", [rc(500, 468, 292, 46, 22)], fill="pink", fo=70),
        G("shine", [line([392, 432], [452, 424]), line([474, 424], [492, 422])], stroke=("white", 9), so=80)])
    add("3d-glasses", "3D glasses", "face", [
        G("temples", both([line([340, 440], [300, 428])]), stroke=("white", 10)),
        G("frame", [rc(500, 452, 336, 104, 16)], fill="white"),
        G("red", [rc(418, 454, 124, 68, 10)], fill="red", fo=88),
        G("blue", [rc(582, 454, 124, 68, 10)], fill="cyan", fo=88)])
    add("visor", "Visor", "face", [
        G("glow", [rc(500, 448, 404, 84, 42)], fill="cyan", fo=28),
        G("band", [rc(500, 448, 384, 62, 31)], fill="cyan", fo=88),
        G("line", [line([330, 448], [670, 448])], stroke=("white", 5), so=70),
        G("shine", [line([344, 434], [420, 432])], stroke=("white", 7), so=85)])
    add("cheek-star", "Cheek star", "face", [
        G("star", [star(350, 526, 40)], fill="gold", stroke=("goldDark", 4))])

    # ---------- neck (under the chin, on the body) ----------
    add("tie", "Tie", "neck", [
        G("blade", [poly([[487, 664], [513, 664], [530, 772], [500, 804], [470, 772]])], fill="blue"),
        G("stripes", [line([481, 706], [521, 722]), line([476, 744], [526, 762])], stroke=("sky", 9)),
        G("knot", [poly([[476, 632], [524, 632], [514, 668], [486, 668]])], fill="blueDark")])
    add("bandana", "Bandana", "neck", [
        G("cloth", [curve([[362, 626], [638, 626], [500, 752]], [[0, 0], [0, 0], [30, -10]], [[0, 0], [0, 0], [-30, -10]], closed=True)], fill="mint"),
        G("dots", [el(450, 660, 13), el(500, 690, 13), el(550, 660, 13), el(500, 646, 13)], fill="white"),
        G("band", [rc(500, 630, 300, 30, 15)], fill="mintDark")])
    add("bell", "Bell collar", "neck", [
        G("collar", [rc(500, 640, 310, 32, 16)], fill="red"),
        G("bell", [el(500, 682, 56)], fill="gold", stroke=("goldDark", 5)),
        G("slot", [line([500, 684], [500, 704])], stroke=("goldDark", 5)),
        G("dot", [el(500, 682, 11)], fill="goldDark")])
    add("pearls", "Pearls", "neck", [
        G("pearls", [el(x, y, 28) for x, y in necklace(11)], fill="pearl", stroke=("silver", 3)),
        G("shine", [el(x - 5, y - 5, 8) for x, y in necklace(11)], fill="white")])
    lei = necklace(8, r=136, drop=76)
    add("lei", "Lei", "neck", [
        G("pink", [el(x, y, 46) for x, y in lei[0::2]], fill="pink"),
        G("gold", [el(x, y, 46) for x, y in lei[1::2]], fill="gold"),
        G("middles", [el(x, y, 16) for x, y in lei], fill="white")])
    add("gold-chain", "Gold chain", "neck", [
        G("chain", [curve([[376, 620], [500, 700], [624, 620]], [[0, 0], [-70, 0], [0, 0]], [[0, 0], [70, 0], [0, 0]])], stroke=("gold", 13)),
        G("links", [curve([[376, 620], [500, 700], [624, 620]], [[0, 0], [-70, 0], [0, 0]], [[0, 0], [70, 0], [0, 0]])], stroke=("goldDark", 3)),
        G("gem", [poly([[500, 700], [530, 734], [500, 780], [470, 734]])], fill="cyan", stroke=("white", 4)),
        G("facet", [poly([[470, 734], [530, 734]], closed=False)], stroke=("white", 3), so=80)])
    add("winter-scarf", "Winter scarf", "neck", [
        G("end L", [rc(430, 700, 52, 118, 18)], fill="mintDark", rot=(430, 700, 7)),
        G("end R", [rc(486, 708, 52, 130, 18)], fill="mint", rot=(486, 708, -4)),
        G("fringe", [line([470, 778], [470, 792]), line([488, 780], [488, 794]), line([506, 778], [506, 792])], stroke=("white", 6)),
        G("wrap", [rc(500, 636, 340, 60, 30)], fill="mint"),
        G("stripes", [line([400, 612], [392, 660]), line([452, 610], [448, 662]), line([548, 610], [552, 662]), line([600, 612], [608, 660])], stroke=("white", 10), so=85)])
    add("amulet", "Amulet", "neck", [
        G("cord", [poly([[392, 618], [500, 716], [608, 618]], closed=False)], stroke=("ink", 6)),
        G("glow", [el(500, 742, 104)], fill="purple", fo=30),
        G("gem", [poly([[500, 700], [536, 722], [536, 762], [500, 784], [464, 762], [464, 722]])], fill="purple", stroke=("gold", 6)),
        G("shine", [poly([[500, 712], [522, 726], [500, 740], [478, 726]])], fill="white", fo=55)])

    # ---------- back (behind the body) ----------
    add("cape", "Cape", "back", [
        G("cape", [curve([[372, 626], [628, 626], [800, 896], [650, 872], [500, 902], [350, 872], [200, 896]], [[0, 0], [0, 0], [-10, -120], [0, 0], [0, 0], [0, 0], [0, 0]], [[0, 0], [70, 60], [0, 0], [0, 0], [0, 0], [0, 0], [10, -120]], closed=True)], fill="red"),
        G("shade", [poly([[420, 640], [580, 640], [640, 880], [360, 880]])], fill="redDark"),
        G("clasp", [el(500, 634, 30)], fill="gold")])
    wing = G("wing L", [curve([[392, 668], [262, 540], [150, 566], [176, 668], [226, 750], [366, 770]], [[0, 0], [50, 10], [30, -40], [-20, -30], [-20, -30], [-50, 10]], [[-40, -60], [-40, -8], [-10, 30], [10, 30], [40, 20], [0, 0]], closed=True)], fill="white", stroke=("silver", 5))
    feathers = G("feathers L", [line([330, 640], [220, 604]), line([340, 690], [226, 680]), line([350, 734], [256, 738])], stroke=("silver", 5))
    add("wings", "Wings", "back", [wing, mirrored(wing, "wing R"), feathers, mirrored(feathers, "feathers R")])
    upper = G("upper L", [el(292, 640, 210, 180)], fill="purple", rot=(292, 640, -24))
    lower = G("lower L", [el(326, 782, 150, 124)], fill="pink", rot=(326, 782, 20))
    spots = G("spots L", [el(262, 620, 48), el(300, 790, 32)], fill="cream", fo=85)
    add("butterfly", "Butterfly wings", "back", [upper, mirrored(upper, "upper R"), lower, mirrored(lower, "lower R"), spots, mirrored(spots, "spots R")])
    add("balloon", "Balloon", "back", [
        G("string", [curve([[352, 770], [238, 520]], [[0, 0], [30, 80]], [[-70, -60], [0, 0]])], stroke=("silver", 5)),
        G("knot", [poly([[238, 500], [226, 526], [250, 526]])], fill="redDark"),
        G("balloon", [el(238, 420, 140, 168)], fill="red"),
        G("shine", [curve([[206, 380], [196, 420]], [[0, 0], [-8, -14]], [[-8, 14], [0, 0]])], stroke=("white", 9), so=70)])
    return P

# ---- drawing: everything becomes polylines ----

def flat(it, steps=18):
    if it[0] == "el":
        _, cx, cy, w, h = it
        return [[cx + w / 2 * math.cos(2 * math.pi * k / 72), cy + h / 2 * math.sin(2 * math.pi * k / 72)] for k in range(72)], True
    if it[0] == "rc":
        _, cx, cy, w, h, r = it
        r = min(r, w / 2, h / 2)
        if r <= 0: return [[cx - w / 2, cy - h / 2], [cx + w / 2, cy - h / 2], [cx + w / 2, cy + h / 2], [cx - w / 2, cy + h / 2]], True
        pts = []
        for (ox, oy, a0) in ((cx + w / 2 - r, cy - h / 2 + r, -90), (cx + w / 2 - r, cy + h / 2 - r, 0), (cx - w / 2 + r, cy + h / 2 - r, 90), (cx - w / 2 + r, cy - h / 2 + r, 180)):
            pts += [[ox + r * math.cos(math.radians(a0 + 90 * k / 10)), oy + r * math.sin(math.radians(a0 + 90 * k / 10))] for k in range(11)]
        return pts, True
    _, v, i, o, closed = it
    n = len(v)
    pts = [list(v[0])]
    for k in range(n if closed else n - 1):
        a, b = v[k], v[(k + 1) % n]
        c1 = [a[0] + o[k][0], a[1] + o[k][1]]
        c2 = [b[0] + i[(k + 1) % n][0], b[1] + i[(k + 1) % n][1]]
        straight = o[k] == [0, 0] and i[(k + 1) % n] == [0, 0]
        for s in range(1, (1 if straight else steps) + 1):
            t = s / (1 if straight else steps)
            pts.append([(1 - t) ** 3 * a[j] + 3 * (1 - t) ** 2 * t * c1[j] + 3 * (1 - t) * t * t * c2[j] + t ** 3 * b[j] for j in (0, 1)])
    if closed: pts.pop()
    return pts, closed

def mul(A, B):  # 2x3 affine: A after B
    return [A[0] * B[0] + A[1] * B[3], A[0] * B[1] + A[1] * B[4], A[0] * B[2] + A[1] * B[5] + A[2],
            A[3] * B[0] + A[4] * B[3], A[3] * B[1] + A[4] * B[4], A[3] * B[2] + A[4] * B[5] + A[5]]

def around(cx, cy, deg, sx=1, sy=1):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [c * sx, -s * sy, cx - c * sx * cx + s * sy * cy, s * sx, c * sy, cy - s * sx * cx - c * sy * cy]

def apply(M, p): return (M[0] * p[0] + M[1] * p[1] + M[2], M[3] * p[0] + M[4] * p[1] + M[5])

def draw(canvas, groups, M, ss):
    """Paints groups (bottom first) through M onto an RGBA canvas that is `ss` times oversampled"""
    scale = math.sqrt(abs(M[0] * M[4] - M[1] * M[3])) * ss
    for g in groups:
        T = mul(M, around(*g["rot"])) if g["rot"] else M
        shapes = []
        for it in g["items"]:
            pts, closed = flat(it)
            shapes.append(([tuple(v * ss for v in apply(T, p)) for p in pts], closed))
        if g["fill"]:
            mask = Image.new("L", canvas.size, 0)
            d = ImageDraw.Draw(mask)
            for pts, closed in shapes:
                if len(pts) >= 3: d.polygon(pts, fill=255)
            paint(canvas, mask, *g["fill"])
        if g["stroke"]:
            rgb, w, op = g["stroke"]
            mask = Image.new("L", canvas.size, 0)
            d = ImageDraw.Draw(mask)
            wd = max(1, w * scale)
            for pts, closed in shapes:
                seq = pts + [pts[0]] if closed else pts
                d.line(seq, fill=255, width=int(round(wd)), joint="curve")
                for p in (seq if closed else [seq[0], seq[-1]]):
                    d.ellipse([p[0] - wd / 2, p[1] - wd / 2, p[0] + wd / 2, p[1] + wd / 2], fill=255)
            paint(canvas, mask, rgb, op)

def paint(canvas, mask, rgb, op):
    if op < 100: mask = mask.point(lambda a: int(a * op / 100))
    colour = Image.new("RGBA", canvas.size, tuple(int(round(c * 255)) for c in rgb) + (255,))
    colour.putalpha(mask)  # the colour itself stays pure where it is see-through
    canvas.alpha_composite(colour)

def render(groups, M, size, ss=4):
    canvas = Image.new("RGBA", (size * ss, size * ss), (0, 0, 0, 0))
    draw(canvas, groups, M, ss)
    return canvas.resize((size, size), Image.LANCZOS)

# ---- reading and writing Lottie ----

def static(prop):
    k = prop["k"]
    return k[0]["s"] if isinstance(k, list) and k and isinstance(k[0], dict) else k

def read_groups(layer):
    out = []
    for s in reversed(layer.get("shapes", [])):
        if s["ty"] != "gr": continue
        items, fill, stroke, rot = [], None, None, None
        for it in s["it"]:
            t = it["ty"]
            if t == "el": items.append(("el", *static(it["p"]), *static(it["s"])))
            elif t == "rc": items.append(("rc", *static(it["p"]), *static(it["s"]), static(it["r"])))
            elif t == "sh":
                k = static(it["ks"])
                k = k[0] if isinstance(k, list) else k
                items.append(("sh", k["v"], k["i"], k["o"], k["c"]))
            elif t == "fl": fill = (tuple(static(it["c"])[:3]), static(it["o"]))
            elif t == "st": stroke = (tuple(static(it["c"])[:3]), static(it["w"]), static(it["o"]))
            elif t == "tr":
                a, r = static(it["a"]), static(it["r"])
                if r: rot = (a[0], a[1], r)
        out.append(dict(name=s["nm"], items=items, fill=fill, stroke=stroke, rot=rot))
    return out

def layer_matrix(layer, by_ind):
    ks = layer["ks"]
    a, p, s, r = static(ks["a"]), static(ks["p"]), static(ks["s"]), static(ks["r"])
    r = r[0] if isinstance(r, list) else r
    c, sn = math.cos(math.radians(r)), math.sin(math.radians(r))
    sx, sy = s[0] / 100, s[1] / 100
    local = [c * sx, -sn * sy, p[0] - c * sx * a[0] + sn * sy * a[1], sn * sx, c * sy, p[1] - sn * sx * a[0] - c * sy * a[1]]
    return mul(layer_matrix(by_ind[layer["parent"]], by_ind), local) if layer.get("parent") else local

def val(k, ix, extra=None):
    d = {"a": 0, "k": k, "ix": ix}
    if extra: d.update(extra)
    return d

def lottie_shape(it, n):
    if it[0] == "el":
        return {"d": 1, "ty": "el", "s": val([it[3], it[4]], 2), "p": val([it[1], it[2]], 3), "nm": "Ellipse Path %d" % n, "mn": "ADBE Vector Shape - Ellipse", "hd": False}
    if it[0] == "rc":
        return {"ty": "rc", "d": 1, "s": val([it[3], it[4]], 2), "p": val([it[1], it[2]], 3), "r": val(it[5], 4), "nm": "Rectangle Path %d" % n, "mn": "ADBE Vector Shape - Rect", "hd": False}
    _, v, i, o, closed = it
    r3 = lambda pts: [[round(x, 3), round(y, 3)] for x, y in pts]
    return {"ind": n - 1, "ty": "sh", "ix": n, "ks": val({"i": r3(i), "o": r3(o), "v": r3(v), "c": closed}, 2), "nm": "Path %d" % n, "mn": "ADBE Vector Shape - Group", "hd": False}

def lottie_group(g, ix):
    it = [lottie_shape(s, n + 1) for n, s in enumerate(g["items"])]
    if g["stroke"]:
        rgb, w, op = g["stroke"]
        it.append({"ty": "st", "c": val(list(rgb) + [1], 3), "o": val(op, 4), "w": val(w, 5), "lc": 2, "lj": 2, "bm": 0, "nm": "Stroke 1", "mn": "ADBE Vector Graphic - Stroke", "hd": False})
    if g["fill"]:
        rgb, op = g["fill"]
        it.append({"ty": "fl", "c": val(list(rgb) + [1], 4), "o": val(op, 5), "r": 1, "bm": 0, "nm": "Fill 1", "mn": "ADBE Vector Graphic - Fill", "hd": False})
    cx, cy, deg = g["rot"] or (0, 0, 0)
    it.append({"ty": "tr", "p": val([cx, cy], 2), "a": val([cx, cy], 1), "s": val([100, 100], 3), "r": val(deg, 6), "o": val(100, 7), "sk": val(0, 4), "sa": val(0, 5), "nm": "Transform"})
    return {"ty": "gr", "it": it, "nm": g["name"], "np": len(it) - 1, "cix": 2, "bm": 0, "ix": ix, "mn": "ADBE Vector Group", "hd": False}

def lottie_layer(piece, ind, parent, op):
    pivot = [500, 450, 0] if parent[0] == "Head" else [500, 640, 0]
    shapes = [lottie_group(g, n + 1) for n, g in enumerate(reversed(piece["groups"]))]  # the top group first
    return {"ddd": 0, "ind": ind, "ty": 4, "nm": piece["layer"], "parent": parent[1], "sr": 1,
            "ks": {"o": val(0, 11), "r": val(0, 10), "p": val(pivot, 2, {"l": 2}), "a": val(pivot, 1, {"l": 2}), "s": val([100, 100, 100], 6, {"l": 2})},
            "ao": 0, "shapes": shapes, "ip": 0, "op": op, "st": 0, "ct": 1, "bm": 0}

def add_to_animation(path, P):
    d = json.load(open(path, encoding="utf-8"))
    mine = {p["layer"] for p in P}
    layers = [l for l in d["layers"] if l["nm"] not in mine]
    names = {l["nm"]: l for l in layers}
    head, body = names["Head"]["ind"], names["Body"]["ind"]
    op = names["Acc Glasses"]["op"]
    ind = max(l["ind"] for l in layers)
    made = {}
    for p in P:
        ind += 1
        made[p["id"]] = lottie_layer(p, ind, ("Head", head) if p["slot"] in ("head", "face") else ("Body", body), op)
    # the order is the stacking, top first: face over head pieces, both over everything; neck pieces just under the head;
    # back pieces behind the tail
    top = [made[p["id"]] for p in P if p["slot"] == "face"] + [made[p["id"]] for p in P if p["slot"] == "head"]
    first_acc = next(n for n, l in enumerate(layers) if l["nm"].startswith("Acc "))
    layers[first_acc:first_acc] = top
    at = next(n for n, l in enumerate(layers) if l["nm"] == "Head") + 1
    layers[at:at] = [made[p["id"]] for p in P if p["slot"] == "neck"]
    at = next(n for n, l in enumerate(layers) if l["nm"] == "Tail") + 1
    layers[at:at] = [made[p["id"]] for p in P if p["slot"] == "back"]
    d["layers"] = layers
    json.dump(d, open(path, "w", encoding="utf-8", newline=""), separators=(",", ":"), ensure_ascii=False)

# ---- the small head pictures ----

def moments(mask):
    px = mask.load()
    w, h = mask.size
    n = sx = sy = 0
    pts = []
    for y in range(h):
        for x in range(w):
            if px[x, y] > 60:
                n += 1; sx += x; sy += y; pts.append((x, y))
    cx, cy = sx / n, sy / n
    xx = sum((x - cx) ** 2 for x, _ in pts) / n
    yy = sum((y - cy) ** 2 for _, y in pts) / n
    xy = sum((x - cx) * (y - cy) for x, y in pts) / n
    return n, cx, cy, 0.5 * math.atan2(2 * xy, xx - yy)

def head_matrix(existing_png, sunglasses):
    """Where the base pose lands in a head picture, from the sunglasses already drawn in it"""
    ref = render(sunglasses, [0.3, 0, 0, 0, 0.3, 0], 300, ss=2).getchannel("A")
    n0, x0, y0, t0 = moments(ref)
    n1, x1, y1, t1 = moments(Image.open(existing_png).convert("RGBA").getchannel("A"))
    s = 0.3 * math.sqrt(n1 / n0)
    turn = t1 - t0
    if turn > math.pi / 2: turn -= math.pi
    if turn < -math.pi / 2: turn += math.pi
    c, sn = math.cos(turn), math.sin(turn)
    bx, by = x0 / 0.3, y0 / 0.3  # the same point in the base pose
    return [s * c, -s * sn, x1 - s * (c * bx - sn * by), s * sn, s * c, y1 - s * (sn * bx + c * by)]

HEADS = {"neutral": "idle", "happy": "happy", "proud": "proud", "sleepy": "sleepy", "sad": "sad", "surprised": "tapped", "eating": "eat", "levelup": "levelup"}

def main():
    ios = sys.argv[1]
    P = pieces()
    assert len({p["id"] for p in P}) == len(P) and len({p["layer"] for p in P}) == len(P)
    anim = ios + "/Cadence/Resources/pip/"
    assets = ios + "/Cadence/Assets.xcassets/"
    idle = json.load(open(anim + "idle.json", encoding="utf-8"))
    names = {l["nm"]: l for l in idle["layers"]}
    sunglasses = read_groups(names["Acc Sunglasses"])
    matrices = {m: head_matrix(assets + "pip-%s-sunglasses.imageset/pip-%s-sunglasses.png" % (m, m), sunglasses) for m in HEADS}

    if len(sys.argv) > 2 and sys.argv[2] == "preview":
        out = sys.argv[3]
        os.makedirs(out, exist_ok=True)
        by_ind = {l["ind"]: l for l in idle["layers"]}
        mine = {p["layer"] for p in P}
        base = [l for l in reversed(idle["layers"]) if not l["nm"].startswith("Acc ") and l["nm"] not in mine]
        size, ss, k = 330, 3, 0.33
        def pip(piece):
            canvas = Image.new("RGBA", (size * ss, size * ss), (38, 36, 48, 255))
            K = [k, 0, 0, 0, k, 0]
            def put(p): draw(canvas, p["groups"], mul(K, layer_matrix(names["Head" if p["slot"] in ("head", "face") else "Body"], by_ind)), ss)
            for l in base:
                if piece and piece["slot"] == "back" and l["nm"] == "Tail": put(piece)
                draw(canvas, read_groups(l), mul(K, layer_matrix(l, by_ind)), ss)
                if piece and piece["slot"] == "neck" and l["nm"] == "Arm R": pass
                if piece and piece["slot"] == "neck" and l["nm"] == "Body": pass
            return canvas
        # the true stacking: neck under the head, so draw in order with the hook at the right layer
        def pip_ordered(piece):
            canvas = Image.new("RGBA", (size * ss, size * ss), (38, 36, 48, 255))
            K = [k, 0, 0, 0, k, 0]
            order = [l["nm"] for l in base]
            for l in base:
                if piece and piece["slot"] == "back" and l["nm"] == order[1]:
                    draw(canvas, piece["groups"], mul(K, layer_matrix(names["Body"], by_ind)), ss)
                if piece and piece["slot"] == "neck" and l["nm"] == "Head":
                    draw(canvas, piece["groups"], mul(K, layer_matrix(names["Body"], by_ind)), ss)
                draw(canvas, read_groups(l), mul(K, layer_matrix(l, by_ind)), ss)
            if piece and piece["slot"] in ("head", "face"):
                draw(canvas, piece["groups"], mul(K, layer_matrix(names["Head"], by_ind)), ss)
            return canvas.resize((size, size), Image.LANCZOS)
        for slot in ("head", "face", "neck", "back"):
            group = [p for p in P if p["slot"] == slot]
            cols = 4
            sheet = Image.new("RGBA", (cols * size, ((len(group) + cols - 1) // cols) * size), (38, 36, 48, 255))
            for n, p in enumerate(group): sheet.paste(pip_ordered(p), ((n % cols) * size, (n // cols) * size))
            sheet.convert("RGB").save(out + "/sheet-%s.png" % slot)
        # the head pictures: the existing headphones redrawn as a check, then a few new pieces in two moods
        checks = Image.new("RGBA", (300 * 4, 300 * 2), (38, 36, 48, 255))
        for row, m in enumerate(("neutral", "sleepy")):
            head = Image.open(assets + "pip-%s.imageset/pip-%s.png" % (m, m)).convert("RGBA")
            for col, groups in enumerate([read_groups(names["Acc Headphones"])] + [next(p for p in P if p["id"] == i)["groups"] for i in ("crown", "heart-glasses", "wizard")]):
                tile = head.copy()
                tile.alpha_composite(render(groups, matrices[m], 300))
                checks.paste(tile, (col * 300, row * 300), tile)
            ours = render(read_groups(names["Acc Headphones"]), matrices[m], 300).getchannel("A").point(lambda a: 255 if a > 60 else 0)
            theirs = Image.open(assets + "pip-%s-headphones.imageset/pip-%s-headphones.png" % (m, m)).convert("RGBA").getchannel("A").point(lambda a: 255 if a > 60 else 0)
            both_ = sum(1 for a, b in zip(ours.tobytes(), theirs.tobytes()) if a and b)
            either = sum(1 for a, b in zip(ours.tobytes(), theirs.tobytes()) if a or b)
            print(m, "headphones overlap", round(both_ / either, 3), "matrix", [round(v, 3) for v in matrices[m]])
        checks.convert("RGB").save(out + "/sheet-heads.png")
        return

    for f in sorted(glob.glob(anim + "*.json")): add_to_animation(f, P)
    count = 0
    for m in HEADS:
        for p in P:
            if p["slot"] not in ("head", "face"): continue
            name = "pip-%s-%s" % (m, p["id"])
            folder = assets + name + ".imageset"
            os.makedirs(folder, exist_ok=True)
            render(p["groups"], matrices[m], 300).save(folder + "/" + name + ".png", optimize=True)
            json.dump({"images": [{"idiom": "universal", "filename": name + ".png", "scale": "3x"}], "info": {"version": 1, "author": "xcode"}}, open(folder + "/Contents.json", "w", encoding="utf-8"))
            count += 1
    print("pieces", len(P), "animations", len(glob.glob(anim + "*.json")), "head pictures", count)

if __name__ == "__main__": main()
