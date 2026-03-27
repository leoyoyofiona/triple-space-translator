#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
SCREENSHOT_DIR = ROOT / "assets" / "screenshots"
OUTPUT_PATH = SCREENSHOT_DIR / "demo-roundtrip.gif"

FRAMES = [
    ("demo-zh-input.png", "1. Type in Chinese"),
    ("demo-zh-input.png", "2. Press Space x3 within 0.5s"),
    ("demo-en-output.png", "3. Replaced with English"),
    ("demo-en-output.png", "4. Press Space x3 again"),
    ("demo-zh-input.png", "5. Toggled back to Chinese"),
]

DURATIONS = [1100, 900, 1200, 900, 1300]
CANVAS_WIDTH = 1200
HEADER_HEIGHT = 72
CAPTION_HEIGHT = 68
CANVAS_BG = "#F5F7FB"
HEADER_BG = "#111827"
CAPTION_BG = "#E9EEF7"
TEXT_DARK = "#111827"
TEXT_LIGHT = "#F9FAFB"


def load_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/Supplemental/Helvetica.ttc",
        "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def fit_image(img: Image.Image, width: int) -> Image.Image:
    ratio = width / img.width
    height = max(1, int(img.height * ratio))
    return img.resize((width, height), Image.LANCZOS)


def render_frame(source_path: Path, caption: str, header_font, caption_font) -> Image.Image:
    screenshot = Image.open(source_path).convert("RGB")
    fitted = fit_image(screenshot, CANVAS_WIDTH)
    canvas_height = HEADER_HEIGHT + fitted.height + CAPTION_HEIGHT
    canvas = Image.new("RGB", (CANVAS_WIDTH, canvas_height), CANVAS_BG)
    draw = ImageDraw.Draw(canvas)

    draw.rectangle((0, 0, CANVAS_WIDTH, HEADER_HEIGHT), fill=HEADER_BG)
    draw.rectangle((0, canvas_height - CAPTION_HEIGHT, CANVAS_WIDTH, canvas_height), fill=CAPTION_BG)
    canvas.paste(fitted, (0, HEADER_HEIGHT))

    header = "Triple Space Translator"
    subheader = "Chinese -> English -> Chinese with triple-space"
    draw.text((28, 18), header, font=header_font, fill=TEXT_LIGHT)
    draw.text((CANVAS_WIDTH - 28, 22), subheader, font=caption_font, fill="#D1D5DB", anchor="ra")
    draw.text((28, canvas_height - 45), caption, font=caption_font, fill=TEXT_DARK)

    return canvas


def main() -> None:
    header_font = load_font(30)
    caption_font = load_font(24)

    frames = []
    for image_name, caption in FRAMES:
        source = SCREENSHOT_DIR / image_name
        frames.append(render_frame(source, caption, header_font, caption_font))

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        OUTPUT_PATH,
        save_all=True,
        append_images=frames[1:],
        duration=DURATIONS,
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"Generated {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
