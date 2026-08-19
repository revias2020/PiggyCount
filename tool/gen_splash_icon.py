#!/usr/bin/env python3
"""从 app_icon 生成启动页专用 splash_icon（ADR-021）。"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "brand" / "app_icon.png"
OUT = ROOT / "assets" / "brand" / "splash_icon.png"
BG = (0x2F, 0x6B, 0xFF, 255)
# 画布边长比例；贴 Android 12 圆裁 2/3 上限（ADR-021 S2）。
SCALE = 0.66


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    if src.size[0] != src.size[1]:
        raise SystemExit(f"app_icon must be square, got {src.size}")
    canvas_size = src.size[0]
    canvas = Image.new("RGBA", (canvas_size, canvas_size), BG)
    fg_size = max(1, int(round(canvas_size * SCALE)))
    fg = src.resize((fg_size, fg_size), Image.Resampling.LANCZOS)
    offset = ((canvas_size - fg_size) // 2, (canvas_size - fg_size) // 2)
    canvas.alpha_composite(fg, dest=offset)
    canvas.convert("RGB").save(OUT, "PNG")
    print(f"wrote {OUT.relative_to(ROOT)} ({canvas_size}px, scale={SCALE})")


if __name__ == "__main__":
    main()
