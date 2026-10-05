"""1024x1024 の正方形の原画から、Mac 版のアプリアイコン (Tanzaku/Assets.xcassets/AppIcon.appiconset) の PNG を作る。

使い方: <Pillow の入った python3> scripts/macos/make_app_icon.py <原画の PNG>
    (Pillow は ~/.claude/skills/ios-app-icon-generator/.venv/bin/python3 に入っている)

macOS はアイコンに角丸のマスクを掛けないため、原画を角丸の正方形のタイルに切り抜き、透明な余白と影を付けた
1024x1024 の画像を作り、それを AppIcon.appiconset/Contents.json の各エントリの大きさに縮小して置く。
各エントリの filename は Contents.json に書き込む。
冪等: 同じ原画で何度実行しても同じ PNG と Contents.json になる。
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

APPICONSET_DIRECTORY = Path(__file__).resolve().parents[2] / "Tanzaku" / "Assets.xcassets" / "AppIcon.appiconset"

# タイルの大きさ・角丸の半径・影は、Apple の macOS 11 以降のアプリアイコンのテンプレート (1024 のキャンバスに
# 824x824・角丸の半径 185.4 のタイルを中央に置き、影は半径 28px・下へ 12px・黒の 50%) に合わせる。
# 出典: https://developer.apple.com/forums/thread/670578
CANVAS_SIZE = 1024
TILE_SIZE = 824
TILE_CORNER_RADIUS = 185.4
SHADOW_BLUR_RADIUS = 28
SHADOW_OFFSET_Y = 12
SHADOW_OPACITY = 0.5

# 角丸の縁のぎざつきを消すため、マスクをこの倍率で描いてから縮小する。4 倍で縁の段差が見えなくなる。
MASK_SUPERSAMPLING = 4


def tile_mask() -> Image.Image:
    """キャンバスの中央に置いたタイルの形を、不透明度 (L モード) で表すマスクを返す。"""
    scaled_canvas_size = CANVAS_SIZE * MASK_SUPERSAMPLING
    tile_origin = (CANVAS_SIZE - TILE_SIZE) // 2 * MASK_SUPERSAMPLING
    tile_end = tile_origin + TILE_SIZE * MASK_SUPERSAMPLING - 1
    mask = Image.new("L", (scaled_canvas_size, scaled_canvas_size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (tile_origin, tile_origin, tile_end, tile_end),
        radius=round(TILE_CORNER_RADIUS * MASK_SUPERSAMPLING),
        fill=255,
    )
    return mask.resize((CANVAS_SIZE, CANVAS_SIZE), Image.LANCZOS)


def master_icon(artwork: Image.Image) -> Image.Image:
    """原画をタイルに切り抜き、影を付けた 1024x1024 の RGBA 画像を返す。"""
    mask = tile_mask()
    tile_origin = (CANVAS_SIZE - TILE_SIZE) // 2
    tile_artwork = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    tile_artwork.paste(
        artwork.convert("RGB").resize((TILE_SIZE, TILE_SIZE), Image.LANCZOS),
        (tile_origin, tile_origin),
    )
    tile_artwork.putalpha(mask)

    shadow = Image.new("RGBA", (CANVAS_SIZE, CANVAS_SIZE), (0, 0, 0, 0))
    shadow.putalpha(
        ImageChops.offset(mask, 0, SHADOW_OFFSET_Y)
        .filter(ImageFilter.GaussianBlur(SHADOW_BLUR_RADIUS))
        .point(lambda alpha: round(alpha * SHADOW_OPACITY))
    )
    return Image.alpha_composite(shadow, tile_artwork)


def icon_filename(image_entry: dict) -> str:
    """Contents.json の 1 エントリ (size と scale) に対応する PNG のファイル名を返す。"""
    return f"icon_{image_entry['size']}{'' if image_entry['scale'] == '1x' else '@' + image_entry['scale']}.png"


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit("Usage: python3 scripts/macos/make_app_icon.py <原画の PNG>")
    icon = master_icon(Image.open(sys.argv[1]))
    contents_path = APPICONSET_DIRECTORY / "Contents.json"
    contents = json.loads(contents_path.read_text())
    for image_entry in contents["images"]:
        pixel_size = int(image_entry["size"].split("x")[0]) * int(image_entry["scale"].rstrip("x"))
        image_entry["filename"] = icon_filename(image_entry)
        icon.resize((pixel_size, pixel_size), Image.LANCZOS).save(APPICONSET_DIRECTORY / image_entry["filename"])
    # Xcode が書く Contents.json と同じ区切り (" : ") にして、Xcode で開いた時の差分を出さない
    contents_path.write_text(json.dumps(contents, indent=2, separators=(",", " : ")) + "\n")


if __name__ == "__main__":
    main()
