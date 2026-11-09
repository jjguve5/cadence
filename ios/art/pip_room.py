# Pip's house: one room, drawn in layers that all share the same square (1000 units, floor line at 640), so the app
# only stacks them: wall, floor, window, wall decoration, the left and right corners, the rug, then Pip.
#
#   python -X utf8 -I ios/art/pip_room.py ios            writes Assets.xcassets/room-<id>.imageset
#   python -X utf8 -I ios/art/pip_room.py ios preview D  draws sample rooms into folder D
import json, math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pip_wardrobe as W
from pip_wardrobe import C, G, el, rc, poly, curve, line, star, dome, arc3
from PIL import Image

C.update(
    wallCream=(0.97, 0.91, 0.8), wallCreamDark=(0.93, 0.85, 0.72), wallSky=(0.62, 0.8, 0.97), wallPink=(1, 0.8, 0.84), wallMint=(0.66, 0.92, 0.84),
    forest=(0.18, 0.42, 0.34), forestLight=(0.27, 0.56, 0.42), night=(0.12, 0.14, 0.34), nightLight=(0.2, 0.24, 0.5), brick=(0.72, 0.36, 0.28),
    mortar=(0.9, 0.78, 0.7), royal=(0.36, 0.2, 0.56), wood=(0.76, 0.54, 0.34), woodDark=(0.62, 0.42, 0.25), woodLight=(0.86, 0.66, 0.45),
    tile=(0.95, 0.95, 0.96), tileDark=(0.25, 0.26, 0.32), marble=(0.9, 0.91, 0.94), vein=(0.72, 0.74, 0.8), grass=(0.45, 0.76, 0.4), grassDark=(0.33, 0.62, 0.32),
    skyDay=(0.55, 0.82, 1), sun=(1, 0.86, 0.3), dusk=(1, 0.6, 0.42), duskTop=(0.6, 0.4, 0.75), space=(0.06, 0.06, 0.16), snow=(0.72, 0.8, 0.9),
    pot=(0.86, 0.47, 0.32), potDark=(0.7, 0.35, 0.24), glass=(0.7, 0.92, 1), teal=(0.16, 0.6, 0.66), yellow=(1, 0.88, 0.4), black=(0.1, 0.09, 0.12),
)

def box(x0, y0, x1, y1, r=0): return rc((x0 + x1) / 2, (y0 + y1) / 2, x1 - x0, y1 - y0, r)

def wall(base, extra): return [G("wall", [box(0, 0, 1000, 640)], fill=base)] + extra + [G("skirting", [box(0, 612, 1000, 640)], fill="white"), G("skirting line", [line([0, 612], [1000, 612])], stroke=("silver", 4))]
def floor(base, extra): return [G("floor", [box(0, 640, 1000, 1000)], fill=base)] + extra + [G("edge", [line([0, 642], [1000, 642])], stroke=("ink", 6), so=18)]

WX0, WY0, WX1, WY1 = 110, 130, 400, 400
def window(sky, inside):
    return [G("sky", [box(WX0, WY0, WX1, WY1, 14)], fill=sky)] + inside + [
        G("bars", [line([(WX0 + WX1) / 2, WY0], [(WX0 + WX1) / 2, WY1]), line([WX0, (WY0 + WY1) / 2], [WX1, (WY0 + WY1) / 2])], stroke=("white", 12)),
        G("frame", [box(WX0, WY0, WX1, WY1, 14)], stroke=("white", 20)),
        G("sill", [box(WX0 - 24, WY1 + 4, WX1 + 24, WY1 + 30, 10)], fill="white", stroke=("silver", 3))]

def rooms():
    rnd = random.Random(7)
    R = []
    def add(id, slot, groups): R.append(dict(id=id, slot=slot, groups=groups))

    # ---------- walls ----------
    add("wall-cream", "wall", wall("wallCream", [G("panel", [line([0, 470], [1000, 470])], stroke=("wallCreamDark", 8))]))
    add("wall-stripes", "wall", wall("wallSky", [G("stripes", [box(x, 0, x + 50, 612) for x in range(25, 1000, 100)], fill="white", fo=38)]))
    add("wall-dots", "wall", wall("wallPink", [G("dots", [el(60 + 110 * c + (55 if r % 2 else 0), 50 + 96 * r, 30) for r in range(6) for c in range(10)], fill="white", fo=70)]))
    add("wall-mint", "wall", wall("wallMint", [G("panel", [box(0, 470, 1000, 612)], fill="white", fo=45), G("rail", [line([0, 470], [1000, 470])], stroke=("white", 10))]))
    leaves = [(40 + 120 * c + (60 if r % 2 else 0), 60 + 110 * r) for r in range(5) for c in range(9)]
    add("wall-forest", "wall", wall("forest", [
        G("leaves a", [el(x, y, 70, 30) for x, y in leaves[0::2]], fill="forestLight", rot=None),
        G("leaves b", [el(x, y, 30, 70) for x, y in leaves[1::2]], fill="forestLight"),
        G("berries", [el(x + 26, y - 20, 14) for x, y in leaves[0::3]], fill="pink")]))
    stars_ = [(rnd.randint(20, 980), rnd.randint(20, 590)) for _ in range(46)]
    add("wall-night", "wall", wall("night", [
        G("glow", [el(760, 150, 420, 300)], fill="nightLight", fo=45),
        G("dust", [el(x, y, 8) for x, y in stars_[:30]], fill="white", fo=80),
        G("stars", [star(x, y, 13) for x, y in stars_[30:]], fill="gold")]))
    mortar = [line([0, y], [1000, y]) for y in range(68, 612, 68)]
    for r, y in enumerate(range(0, 612, 68)):
        mortar += [line([x, y], [x, min(y + 68, 612)]) for x in range(70 if r % 2 else 0, 1001, 140)]
    add("wall-brick", "wall", wall("brick", [G("mortar", mortar, stroke=("mortar", 7))]))
    diamonds = [(c * 125 + (62 if r % 2 else 0), 20 + r * 100) for r in range(7) for c in range(9)]
    add("wall-royal", "wall", wall("royal", [
        G("diamonds", [poly([[x, y - 34], [x + 26, y], [x, y + 34], [x - 26, y]]) for x, y in diamonds], stroke=("gold", 4), so=85),
        G("pips", [el(x, y, 10) for x, y in diamonds], fill="gold"),
        G("rail", [box(0, 588, 1000, 612)], fill="gold")]))

    # ---------- floors ----------
    planks = [line([0, y], [1000, y]) for y in (730, 820, 910)]
    for r, (y0, y1) in enumerate(((640, 730), (730, 820), (820, 910), (910, 1000))):
        planks += [line([x, y0], [x, y1]) for x in range(160 if r % 2 else 320, 1000, 330)]
    add("floor-wood", "floor", floor("wood", [G("planks", planks, stroke=("woodDark", 6))]))
    add("floor-check", "floor", floor("tile", [G("dark", [box(c * 100, 640 + r * 90, c * 100 + 100, 730 + r * 90) for r in range(4) for c in range(10) if (r + c) % 2], fill="tileDark")]))
    add("floor-carpet", "floor", floor("teal", [G("pile", [el(rnd.randint(10, 990), rnd.randint(660, 990), 10) for _ in range(160)], fill="white", fo=20)]))
    add("floor-grass", "floor", floor("grass", [
        G("tufts", [poly([[x, y], [x + 8, y - 26], [x + 16, y]]) for x, y in [(rnd.randint(10, 970), rnd.randint(690, 990)) for _ in range(60)]], fill="grassDark"),
        G("daisies", [el(x, y, 16) for x, y in [(rnd.randint(30, 970), rnd.randint(700, 980)) for _ in range(12)]], fill="white")]))
    add("floor-marble", "floor", floor("marble", [
        G("veins", [curve([[x, 640], [x + 120, 820], [x + 60, 1000]], [[0, 0], [-60, -60], [40, -60]], [[20, 70], [40, 60], [0, 0]]) for x in (80, 380, 640, 860)], stroke=("vein", 6)),
        G("tiles", [line([0, 820], [1000, 820]), line([333, 640], [333, 1000]), line([666, 640], [666, 1000])], stroke=("white", 6))]))

    # ---------- windows ----------
    add("window-day", "window", window("skyDay", [
        G("sun", [el(340, 190, 64)], fill="sun"),
        G("cloud", [el(190, 300, 90, 50), el(240, 284, 80, 60), el(280, 304, 80, 44)], fill="white")]))
    add("window-sunset", "window", window("dusk", [
        G("top", [box(WX0, WY0, WX1, 220, 14)], fill="duskTop", fo=70),
        G("sun", [el(255, 352, 96)], fill="sun"),
        G("sea", [box(WX0, 360, WX1, WY1)], fill="purpleDark", fo=85)]))
    add("window-night", "window", window("night", [
        G("moon", [el(320, 210, 84)], fill="cream"),
        G("bite", [el(346, 196, 70)], fill="night"),
        G("stars", [star(170, 190, 13), star(230, 320, 10), star(150, 300, 8), star(340, 340, 9)], fill="gold")]))
    add("window-snow", "window", window("snow", [
        G("hill", [curve([[110, 400], [110, 366], [255, 328], [400, 366], [400, 400]], [[0, 0], [0, 0], [-70, 0], [0, 0], [0, 0]], [[0, 0], [0, 0], [70, 0], [0, 0], [0, 0]], closed=True)], fill="white"),
        G("tree", [poly([[180, 350], [210, 270], [240, 350]]), poly([[188, 310], [210, 250], [232, 310]])], fill="forestLight"),
        G("flakes", [el(x, y, 11) for x, y in [(150, 170), (210, 210), (290, 170), (350, 240), (310, 300), (160, 250), (370, 160), (250, 250)]], fill="white")]))
    add("window-space", "window", window("space", [
        G("stars", [el(x, y, 7) for x, y in [(150, 170), (200, 330), (300, 160), (370, 300), (340, 370), (160, 270), (250, 220)]], fill="white"),
        G("ring back", [el(270, 270, 230, 60)], stroke=("gold", 9), rot=(270, 270, -18)),
        G("planet", [el(270, 270, 130)], fill="orange"),
        G("band", [line([216, 262], [324, 250])], stroke=("pink", 14), so=70)]))

    # ---------- rugs ----------
    add("rug-round", "rug", [G("rug", [el(500, 880, 560, 150)], fill="mint"), G("ring", [el(500, 880, 440, 104)], stroke=("white", 9), so=80)])
    add("rug-stripes", "rug", [G("rug", [box(230, 810, 770, 950, 26)], fill="red"), G("stripes", [box(x, 810, x + 46, 950) for x in (300, 430, 560, 660)], fill="cream", fo=90),
                               G("fringe", [line([x, 950], [x, 968]) for x in range(250, 770, 26)], stroke=("cream", 6))])
    add("rug-star", "rug", [G("rug", [el(500, 880, 560, 150)], fill="blue"), G("star", [("sh", [[x, 880 + (y - 880) * 0.42] for x, y in star(500, 880, 150)[1]], [[0, 0]] * 10, [[0, 0]] * 10, True)], fill="gold"), G("edge", [el(500, 880, 520, 124)], stroke=("sky", 6))])
    add("rug-heart", "rug", [G("rug", [el(500, 880, 560, 150)], fill="pink"), G("heart", [el(464, 864, 92, 52), el(536, 864, 92, 52), poly([[420, 870], [580, 870], [500, 934]])], fill="white")])

    # ---------- the left corner ----------
    add("left-plant", "left", [
        G("stems", [curve([[200, 770], [150, 600]], [[0, 0], [20, 60]], [[-10, -60], [0, 0]]), curve([[200, 770], [260, 580]], [[0, 0], [-10, 60]], [[10, -60], [0, 0]]), line([200, 770], [200, 560])], stroke=("leafDark", 9)),
        G("leaves", [el(140, 590, 110, 54), el(270, 568, 120, 56), el(200, 540, 70, 120), el(160, 680, 96, 46), el(250, 670, 96, 46)], fill="leaf"),
        G("veins", [line([110, 590], [170, 590]), line([240, 568], [300, 568]), line([200, 500], [200, 580])], stroke=("leafDark", 5)),
        G("pot", [poly([[130, 770], [270, 770], [250, 900], [150, 900]])], fill="pot"),
        G("rim", [box(120, 756, 280, 792, 12)], fill="potDark")])
    add("left-cactus", "left", [
        G("arms", [curve([[200, 720], [130, 700], [130, 630]], [[0, 0], [30, 20], [0, 0]], [[0, 0], [0, -30], [0, 0]]), curve([[200, 680], [270, 660], [270, 600]], [[0, 0], [-30, 20], [0, 0]], [[0, 0], [0, -30], [0, 0]])], stroke=("leafDark", 44)),
        G("body", [box(164, 540, 236, 800, 36)], fill="leaf"),
        G("spines", [line([200, 570], [200, 590]), line([186, 640], [186, 660]), line([214, 700], [214, 720]), line([130, 650], [130, 668]), line([270, 620], [270, 638])], stroke=("cream", 5)),
        G("flower", [el(200, 536, 40)], fill="pink"),
        G("pot", [poly([[140, 790], [260, 790], [244, 900], [156, 900]])], fill="yellow"),
        G("rim", [box(130, 776, 270, 810, 12)], fill="orange")])
    books = [(92, "red", 96), (128, "blue", 110), (168, "gold", 88), (204, "mint", 104), (246, "purple", 96), (284, "pink", 112)]
    add("left-bookshelf", "left", [
        G("case", [box(60, 440, 330, 900, 10)], fill="woodDark"),
        G("back", [box(78, 458, 312, 882, 6)], fill="wood")] +
        [G("books %d" % n, [box(x, yb - h, x + 30, yb) for (x, col, h) in books if col == c for yb in (590, 740)], fill=c) for n, c in enumerate(("red", "blue", "gold", "mint", "purple", "pink"))] + [
        G("vase", [el(196, 838, 60, 76)], fill="cyan"),
        G("shelves", [box(60, 590, 330, 606), box(60, 740, 330, 756)], fill="woodDark")])
    add("left-lamp", "left", [
        G("glow", [el(200, 470, 380)], fill="yellow", fo=22),
        G("pole", [line([200, 560], [200, 880])], stroke=("grey", 12)),
        G("base", [el(200, 890, 130, 34)], fill="grey"),
        G("shade", [poly([[150, 420], [250, 420], [286, 570], [114, 570]])], fill="yellow", stroke=("orange", 6)),
        G("pull", [line([232, 570], [232, 620])], stroke=("grey", 4)), G("knob", [el(232, 624, 12)], fill="gold")])
    add("left-aquarium", "left", [
        G("stand", [box(70, 780, 330, 900, 8)], fill="woodDark"), G("door", [box(90, 800, 310, 884, 6)], fill="wood"),
        G("water", [box(80, 590, 320, 780, 12)], fill="glass"),
        G("weed", [curve([[120, 776], [130, 690]], [[0, 0], [-20, 30]], [[20, -30], [0, 0]]), curve([[290, 776], [280, 710]], [[0, 0], [20, 20]], [[-20, -20], [0, 0]])], stroke=("leaf", 10)),
        G("fish", [el(210, 670, 64, 40), poly([[240, 670], [270, 650], [270, 690]])], fill="orange"),
        G("fish 2", [el(150, 720, 40, 26), poly([[132, 720], [112, 708], [112, 732]])], fill="pink"),
        G("eye", [el(194, 664, 9)], fill="ink"),
        G("bubbles", [el(250, 630, 14), el(262, 606, 10)], stroke=("white", 4)),
        G("tank", [box(80, 590, 320, 780, 12)], stroke=("white", 9)),
        G("sand", [box(86, 760, 314, 776, 6)], fill="cream")])

    # ---------- the right corner ----------
    add("right-armchair", "right", [
        G("legs", [box(716, 880, 736, 910, 4), box(900, 880, 920, 910, 4)], fill="woodDark"),
        G("back", [box(700, 600, 936, 860, 60)], fill="red"),
        G("arms", [box(676, 730, 740, 890, 30), box(896, 730, 960, 890, 30)], fill="redDark"),
        G("seat", [box(730, 770, 906, 880, 26)], fill="pink"),
        G("button", [el(818, 680, 18)], fill="redDark")])
    add("right-bed", "right", [
        G("head", [box(900, 590, 960, 900, 20)], fill="woodDark"),
        G("frame", [box(640, 800, 950, 900, 14)], fill="wood"),
        G("mattress", [box(640, 740, 940, 820, 26)], fill="white"),
        G("blanket", [box(640, 746, 840, 830, 26)], fill="blue"),
        G("fold", [box(820, 746, 860, 830, 12)], fill="sky"),
        G("pillow", [box(858, 700, 940, 760, 24)], fill="cream", stroke=("silver", 3)),
        G("stars", [star(700, 790, 14), star(770, 780, 10)], fill="gold")])
    add("right-beanbag", "right", [
        G("bag", [curve([[690, 900], [700, 740], [820, 660], [930, 760], [940, 900]], [[0, 0], [-30, 60], [-60, 0], [-10, -50], [0, 0]], [[-30, -60], [10, -50], [60, 0], [30, 60], [0, 0]], closed=True)], fill="purple"),
        G("dent", [el(812, 760, 150, 60)], fill="purpleDark", fo=70),
        G("seam", [curve([[720, 880], [900, 880]], [[0, 0], [-60, 30]], [[60, 30], [0, 0]])], stroke=("purpleDark", 6))])
    add("right-table", "right", [
        G("legs", [line([730, 780], [716, 900]), line([890, 780], [904, 900])], stroke=("woodDark", 16)),
        G("top", [box(680, 756, 940, 790, 14)], fill="wood"),
        G("cake", [box(720, 700, 800, 756, 8)], fill="cream"), G("icing", [box(720, 696, 800, 716, 8)], fill="pink"), G("cherry", [el(760, 688, 20)], fill="red"),
        G("pot", [el(866, 724, 76, 64)], fill="white", stroke=("silver", 4)),
        G("spout", [curve([[900, 730], [930, 700]], [[0, 0], [-10, 16]], [[16, 0], [0, 0]])], stroke=("white", 12)),
        G("lid", [el(866, 692, 22)], fill="mint")])
    add("right-arcade", "right", [
        G("cabinet", [poly([[700, 900], [700, 520], [740, 470], [920, 470], [920, 900]])], fill="purpleDark"),
        G("side", [box(700, 560, 716, 900)], fill="purple"),
        G("marquee", [box(740, 486, 906, 530, 8)], fill="gold"),
        G("screen", [box(740, 548, 906, 680, 10)], fill="black"),
        G("game", [star(790, 610, 20), el(850, 630, 22)], fill="mint"),
        G("ship", [poly([[820, 660], [832, 640], [844, 660]])], fill="pink"),
        G("panel", [poly([[726, 700], [920, 700], [920, 750], [706, 750]])], fill="grey"),
        G("stick", [line([770, 724], [770, 690])], stroke=("silver", 8)), G("ball", [el(770, 686, 24)], fill="red"),
        G("buttons", [el(840, 724, 22), el(880, 724, 22)], fill="gold"),
        G("coin", [box(790, 800, 850, 850, 6)], fill="black")])
    coins = [(x, y) for y in (876, 852, 828) for x in range(730, 900, 34)]
    add("right-treasure", "right", [
        G("pile", [el(815, 880, 300, 90)], fill="goldDark"),
        G("coins", [el(x + (17 if y == 852 else 0), y, 44, 26) for x, y in coins], fill="gold", stroke=("goldDark", 4)),
        G("cup", [poly([[790, 760], [860, 760], [846, 820], [804, 820]])], fill="gold", stroke=("goldDark", 5)),
        G("stem", [box(816, 820, 834, 846)], fill="goldDark"),
        G("gems", [poly([[720, 840], [738, 818], [756, 840], [738, 862]]), poly([[892, 850], [908, 830], [924, 850], [908, 870]])], fill="cyan", stroke=("white", 3)),
        G("ruby", [el(760, 800, 26)], fill="red"),
        G("sparkles", [star(700, 780, 14, points=4, inner=0.3), star(930, 790, 12, points=4, inner=0.3), star(826, 730, 12, points=4, inner=0.3)], fill="white")])

    # ---------- on the wall ----------
    add("decor-picture", "decor", [
        G("frame", [box(600, 170, 860, 370, 10)], fill="woodDark"),
        G("sky", [box(618, 188, 842, 352, 4)], fill="skyDay"),
        G("sun", [el(800, 226, 40)], fill="sun"),
        G("far", [poly([[618, 352], [700, 240], [780, 352]])], fill="purple"),
        G("near", [poly([[690, 352], [776, 270], [842, 340], [842, 352]])], fill="forestLight"),
        G("snow", [poly([[683, 263], [700, 240], [717, 263]])], fill="white")])
    add("decor-clock", "decor", [
        G("body", [el(730, 260, 180)], fill="white", stroke=("woodDark", 16)),
        G("ticks", [line([730, 190], [730, 204]), line([730, 316], [730, 330]), line([660, 260], [674, 260]), line([786, 260], [800, 260])], stroke=("grey", 7)),
        G("hands", [line([730, 260], [730, 212]), line([730, 260], [768, 282])], stroke=("ink", 9)),
        G("pin", [el(730, 260, 16)], fill="red")])
    flags = [(80 + 105 * i, 70 + 34 * math.sin(math.pi * i / 8)) for i in range(9)]
    add("decor-bunting", "decor", [
        G("string", [curve([[0, 40], [500, 112], [1000, 40]], [[0, 0], [-220, 0], [0, 0]], [[0, 0], [220, 0], [0, 0]])], stroke=("ink", 5), so=60)] +
        [G("flags %s" % c, [poly([[x - 34, y], [x + 34, y], [x, y + 72]]) for n, (x, y) in enumerate(flags) if n % 4 == k], fill=c) for k, c in enumerate(("red", "gold", "mint", "blue"))])
    add("decor-trophy", "decor", [
        G("bracket", [line([640, 330], [640, 370]), line([840, 330], [840, 370])], stroke=("woodDark", 10)),
        G("shelf", [box(600, 320, 880, 344, 8)], fill="wood"),
        G("handles", [el(700, 236, 100, 60)], stroke=("gold", 9)),
        G("cup", [poly([[664, 200], [736, 200], [722, 276], [678, 276]])], fill="gold", stroke=("goldDark", 5)),
        G("foot", [box(690, 276, 710, 304), box(672, 300, 728, 320, 4)], fill="goldDark"),
        G("star", [star(700, 236, 16)], fill="white"),
        G("medal", [el(810, 286, 50)], fill="silver", stroke=("greyLight", 5)), G("ribbon", [poly([[796, 244], [824, 244], [818, 266], [802, 266]])], fill="blue")])
    bulbs = [(40 + 115 * i, 56 + 46 * math.sin(math.pi * i / 8)) for i in range(9)]
    add("decor-lights", "decor", [
        G("wire", [curve([[0, 30], [500, 124], [1000, 30]], [[0, 0], [-220, 0], [0, 0]], [[0, 0], [220, 0], [0, 0]])], stroke=("ink", 5), so=70),
        G("glow", [el(x, y + 22, 76) for x, y in bulbs], fill="yellow", fo=26)] +
        [G("bulbs %s" % c, [el(x, y + 22, 30, 40) for n, (x, y) in enumerate(bulbs) if n % 4 == k], fill=c) for k, c in enumerate(("yellow", "pink", "cyan", "mint"))])
    add("decor-poster", "decor", [
        G("paper", [box(630, 150, 830, 390, 6)], fill="night"),
        G("rocket", [curve([[730, 200], [770, 290], [690, 290]], [[0, 0], [0, -50], [0, 0]], [[0, 0], [0, 0], [0, -50]], closed=True)], fill="white"),
        G("window", [el(730, 258, 30)], fill="cyan"),
        G("fins", [poly([[690, 290], [668, 322], [700, 310]]), poly([[770, 290], [792, 322], [760, 310]])], fill="red"),
        G("flame", [poly([[712, 296], [748, 296], [730, 350]])], fill="orange"),
        G("stars", [star(660, 190, 10), star(800, 200, 12), star(790, 350, 9), star(660, 360, 8)], fill="gold"),
        G("tape", [box(710, 140, 750, 160, 3)], fill="cream", fo=85)])
    return R

SIZE = 600

def picture(groups, size=SIZE): return W.render(groups, [size / 1000, 0, 0, 0, size / 1000, 0], size, ss=3)

def main():
    ios = sys.argv[1]
    R = rooms()
    assert len({r["id"] for r in R}) == len(R)
    by = {r["id"]: r for r in R}
    if len(sys.argv) > 2 and sys.argv[2] == "preview":
        out = sys.argv[3]
        os.makedirs(out, exist_ok=True)
        idle = json.load(open(ios + "/Cadence/Resources/pip/idle.json", encoding="utf-8"))
        by_ind = {l["ind"]: l for l in idle["layers"]}
        base = [l for l in reversed(idle["layers"]) if not l["nm"].startswith("Acc ")]
        K = [0.5, 0, 250, 0, 0.5, 408]
        looks = [["wall-cream", "floor-wood", "window-day", "decor-picture", "left-plant", "right-armchair", "rug-round"],
                 ["wall-stripes", "floor-check", "window-sunset", "decor-clock", "left-bookshelf", "right-bed", "rug-stripes"],
                 ["wall-dots", "floor-carpet", "window-snow", "decor-bunting", "left-cactus", "right-beanbag", "rug-heart"],
                 ["wall-forest", "floor-grass", "window-night", "decor-trophy", "left-lamp", "right-table", "rug-star"],
                 ["wall-night", "floor-marble", "window-space", "decor-lights", "left-aquarium", "right-arcade"],
                 ["wall-royal", "floor-marble", "window-night", "decor-poster", "left-lamp", "right-treasure", "rug-star"],
                 ["wall-brick", "floor-wood", "window-day", "decor-poster", "left-plant", "right-arcade"],
                 ["wall-mint", "floor-wood", "window-day"]]
        s = 500
        sheet = Image.new("RGBA", (s * 4, s * 2), (38, 36, 48, 255))
        for n, look in enumerate(looks):
            room = Image.new("RGBA", (s * 2, s * 2), (0, 0, 0, 0))
            for id in look: W.draw(room, by[id]["groups"], [s / 1000, 0, 0, 0, s / 1000, 0], 2)
            for l in base: W.draw(room, W.read_groups(l), W.mul([s / 1000, 0, 0, 0, s / 1000, 0], W.mul(K, W.layer_matrix(l, by_ind))), 2)
            sheet.paste(room.resize((s, s), Image.LANCZOS), ((n % 4) * s, (n // 4) * s))
        sheet.convert("RGB").save(out + "/sheet-rooms.png")
        return
    total = 0
    for r in R:
        name = "room-" + r["id"]
        folder = ios + "/Cadence/Assets.xcassets/" + name + ".imageset"
        os.makedirs(folder, exist_ok=True)
        im = picture(r["groups"])
        if r["slot"] in ("wall", "floor"): im = im.convert("RGBA")
        im.save(folder + "/" + name + ".png", optimize=True)
        total += os.path.getsize(folder + "/" + name + ".png")
        json.dump({"images": [{"idiom": "universal", "filename": name + ".png", "scale": "2x"}], "info": {"version": 1, "author": "xcode"}}, open(folder + "/Contents.json", "w", encoding="utf-8"))
    print("room pieces", len(R), "kB", total // 1024, {s: sum(1 for r in R if r["slot"] == s) for s in ("wall", "floor", "window", "rug", "left", "right", "decor")})

if __name__ == "__main__": main()
