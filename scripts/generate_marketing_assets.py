#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
ASSETS_DIR = ROOT / "assets"
SCREENSHOT_DIR = ASSETS_DIR / "screenshots"
MARKETING_DIR = ASSETS_DIR / "marketing"
ICON_PATH = ASSETS_DIR / "macos" / "TripleSpaceTranslator.iconset" / "icon_512x512.png"
ZH_INPUT = SCREENSHOT_DIR / "demo-zh-input.png"
EN_OUTPUT = SCREENSHOT_DIR / "demo-en-output.png"
GIF_PATH = SCREENSHOT_DIR / "demo-live-roundtrip.gif"
HERO_PATH = MARKETING_DIR / "github-hero.png"
RELEASE_COVER_PATH = MARKETING_DIR / "release-cover.png"


def font(size: int, *, mono: bool = False, chinese: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if mono:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Andale Mono.ttf",
                "/System/Library/Fonts/Supplemental/Courier New.ttf",
            ]
        )
    elif chinese:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
                "/System/Library/Fonts/Supplemental/PingFang.ttc",
                "/System/Library/Fonts/Supplemental/Heiti SC.ttc",
            ]
        )
    else:
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Futura.ttc",
                "/System/Library/Fonts/Supplemental/AmericanTypewriter.ttc",
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            ]
        )

    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            return ImageFont.truetype(str(path), size=size)
    return ImageFont.load_default()


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def add_shadow(base: Image.Image, box: tuple[int, int], size: tuple[int, int], radius: int = 28, blur: int = 24, alpha: int = 90) -> None:
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=(15, 23, 42, alpha))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(shadow, (box[0] - blur // 2, box[1] - blur // 2))


def fit_cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    return ImageOps.fit(img, size, method=Image.LANCZOS)


def fit_contain(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    copy = img.copy()
    copy.thumbnail(size, Image.LANCZOS)
    canvas = Image.new("RGBA", size, "#F8FAFC")
    x = (size[0] - copy.width) // 2
    y = (size[1] - copy.height) // 2
    canvas.paste(copy.convert("RGBA"), (x, y))
    return canvas


def paste_card(base: Image.Image, img: Image.Image, xy: tuple[int, int], size: tuple[int, int], radius: int = 28, mode: str = "cover") -> None:
    add_shadow(base, xy, size, radius=radius)
    if mode == "contain":
        card = fit_contain(img, size).convert("RGBA")
    else:
        card = fit_cover(img, size).convert("RGBA")
    mask = rounded_mask(size, radius)
    base.paste(card, xy, mask)


def draw_chip(draw: ImageDraw.ImageDraw, xy: tuple[int, int], label: str, *, fill: str, stroke: str, text_fill: str, padding_x: int = 20, padding_y: int = 10) -> tuple[int, int]:
    chip_font = font(28, chinese=any(ord(c) > 127 for c in label))
    bbox = draw.textbbox((0, 0), label, font=chip_font)
    width = bbox[2] - bbox[0] + padding_x * 2
    height = bbox[3] - bbox[1] + padding_y * 2
    draw.rounded_rectangle((xy[0], xy[1], xy[0] + width, xy[1] + height), radius=height // 2, fill=fill, outline=stroke, width=2)
    draw.text((xy[0] + padding_x, xy[1] + padding_y - 2), label, font=chip_font, fill=text_fill)
    return width, height


def draw_gradient_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    canvas = Image.new("RGBA", size, "#09111f")
    draw = ImageDraw.Draw(canvas)
    for y in range(height):
        t = y / max(1, height - 1)
        r = int(9 + (22 - 9) * t)
        g = int(17 + (39 - 17) * t)
        b = int(31 + (56 - 31) * t)
        draw.line((0, y, width, y), fill=(r, g, b, 255))

    glows = [
        ((-140, -80, 620, 580), (29, 190, 182, 120)),
        ((980, 40, 1600, 760), (245, 158, 11, 110)),
        ((720, 420, 1320, 980), (59, 130, 246, 110)),
    ]
    for box, color in glows:
        glow = Image.new("RGBA", size, (0, 0, 0, 0))
        gdraw = ImageDraw.Draw(glow)
        gdraw.ellipse(box, fill=color)
        glow = glow.filter(ImageFilter.GaussianBlur(90))
        canvas.alpha_composite(glow)
    return canvas


def build_hero() -> Image.Image:
    size = (1600, 900)
    canvas = draw_gradient_background(size)
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(ICON_PATH).convert("RGBA").resize((138, 138), Image.LANCZOS)
    icon_mask = rounded_mask(icon.size, 32)
    add_shadow(canvas, (110, 92), icon.size, radius=32, blur=26, alpha=120)
    canvas.paste(icon, (110, 92), icon_mask)

    title_font = font(84)
    body_font = font(34, chinese=True)
    small_font = font(30)
    mono_font = font(30, mono=True)

    draw.text((280, 104), "Type in Chinese.", font=title_font, fill="#F8FAFC")
    draw.text((280, 194), "Send in English.", font=title_font, fill="#6EE7D8")
    draw.text((116, 284), "三连空格，输入不中断。再次三连空格，立即切回原语言。", font=body_font, fill="#DDE7F5")
    draw.text((116, 336), "Built for AI chats, browser search, and fast bilingual writing.", font=small_font, fill="#AFC4DC")

    chip_x = 116
    for label, fill, stroke, text_fill in [
        ("macOS native", "#112334", "#2dd4bf", "#D9FBF3"),
        ("Round-trip toggle", "#172554", "#60a5fa", "#E0ECFF"),
        ("AI chat ready", "#2B1A08", "#f59e0b", "#FFF2D6"),
    ]:
        w, _ = draw_chip(draw, (chip_x, 406), label, fill=fill, stroke=stroke, text_fill=text_fill)
        chip_x += w + 18

    draw.text((116, 496), "Trigger:", font=small_font, fill="#93C5FD")
    draw.text((246, 494), "Space x3 within 0.5s", font=mono_font, fill="#F8FAFC")
    draw.text((116, 548), "Best for ChatGPT, Claude, Grok, Gemini, search bars, and everyday text boxes.", font=small_font, fill="#CBD5E1")

    zh = Image.open(ZH_INPUT).convert("RGB")
    en = Image.open(EN_OUTPUT).convert("RGB")
    paste_card(canvas, zh, (930, 134), (560, 170), radius=30, mode="contain")
    paste_card(canvas, en, (860, 338), (600, 168), radius=30, mode="contain")

    arrow = Image.new("RGBA", size, (0, 0, 0, 0))
    adraw = ImageDraw.Draw(arrow)
    adraw.rounded_rectangle((1138, 292, 1298, 364), radius=36, fill="#F8FAFC")
    adraw.text((1170, 307), "Space x3", font=font(28), fill="#0F172A")
    adraw.polygon([(1208, 364), (1230, 404), (1262, 364)], fill="#F8FAFC")
    arrow = arrow.filter(ImageFilter.GaussianBlur(0.5))
    canvas.alpha_composite(arrow)

    footer = Image.new("RGBA", size, (0, 0, 0, 0))
    fdraw = ImageDraw.Draw(footer)
    fdraw.rounded_rectangle((110, 736, 1490, 820), radius=32, fill=(15, 23, 42, 160), outline=(148, 163, 184, 80), width=2)
    fdraw.text((148, 760), "One input box. Two languages. No copy-paste detour.", font=font(36), fill="#F8FAFC")
    canvas.alpha_composite(footer)
    return canvas.convert("RGB")


def overlay_space_indicator(frame: Image.Image, count: int, label: str) -> Image.Image:
    result = frame.copy().convert("RGBA")
    draw = ImageDraw.Draw(result)
    panel = (140, result.height - 154, 1060, result.height - 54)
    draw.rounded_rectangle(panel, radius=30, fill=(9, 17, 31, 210), outline=(99, 102, 241, 120), width=2)
    draw.text((174, panel[1] + 18), label, font=font(34), fill="#F8FAFC")
    key_x = 670
    for idx in range(3):
        fill = "#34D399" if idx < count else "#27364F"
        stroke = "#6EE7D8" if idx < count else "#475569"
        text_fill = "#06281F" if idx < count else "#CBD5E1"
        w, _ = draw_chip(draw, (key_x, panel[1] + 16), "Space", fill=fill, stroke=stroke, text_fill=text_fill, padding_x=22, padding_y=10)
        key_x += w + 18
    return result


def compose_demo_frame(screenshot: Image.Image, title: str, subtitle: str) -> Image.Image:
    size = (1360, 760)
    canvas = draw_gradient_background(size)
    draw = ImageDraw.Draw(canvas)

    draw.text((90, 74), title, font=font(58), fill="#F8FAFC")
    draw.text((90, 144), subtitle, font=font(30, chinese=True), fill="#C7D2FE")

    paste_card(canvas, screenshot, (90, 236), (1180, 300), radius=34, mode="contain")

    hint = Image.new("RGBA", size, (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(hint)
    hdraw.rounded_rectangle((90, 584, 1270, 660), radius=28, fill=(255, 255, 255, 34), outline=(148, 163, 184, 70), width=2)
    hdraw.text((122, 605), "Works best in AI chats, search boxes, and fast bilingual drafting.", font=font(28), fill="#E2E8F0")
    canvas.alpha_composite(hint)
    return canvas.convert("RGBA")


def blend(a: Image.Image, b: Image.Image, steps: int) -> list[Image.Image]:
    frames = []
    for idx in range(1, steps + 1):
        frames.append(Image.blend(a, b, idx / steps))
    return frames


def build_demo_gif() -> None:
    zh = Image.open(ZH_INPUT).convert("RGB")
    en = Image.open(EN_OUTPUT).convert("RGB")
    zh_frame = compose_demo_frame(zh, "Type in Chinese first", "先自然输入中文，再用三连空格切换")
    en_frame = compose_demo_frame(en, "Translated in place", "不离开当前输入框，直接替换成英文")

    frames: list[Image.Image] = []
    durations: list[int] = []

    sequence = [
        (zh_frame, 0, "Typing in Chinese", 900),
        (zh_frame, 1, "Press Space x3 within 0.5s", 220),
        (zh_frame, 2, "Press Space x3 within 0.5s", 220),
        (zh_frame, 3, "Press Space x3 within 0.5s", 500),
    ]
    for base, count, label, duration in sequence:
        frames.append(overlay_space_indicator(base, count, label).convert("P", palette=Image.ADAPTIVE))
        durations.append(duration)

    for frame in blend(overlay_space_indicator(zh_frame, 3, "Press Space x3 within 0.5s"), en_frame, 5):
        frames.append(frame.convert("P", palette=Image.ADAPTIVE))
        durations.append(120)

    frames.append(overlay_space_indicator(en_frame, 0, "Now in English").convert("P", palette=Image.ADAPTIVE))
    durations.append(950)

    sequence_back = [
        (en_frame, 1, "Press Space x3 again to toggle back", 220),
        (en_frame, 2, "Press Space x3 again to toggle back", 220),
        (en_frame, 3, "Press Space x3 again to toggle back", 500),
    ]
    for base, count, label, duration in sequence_back:
        frames.append(overlay_space_indicator(base, count, label).convert("P", palette=Image.ADAPTIVE))
        durations.append(duration)

    for frame in blend(overlay_space_indicator(en_frame, 3, "Press Space x3 again to toggle back"), zh_frame, 5):
        frames.append(frame.convert("P", palette=Image.ADAPTIVE))
        durations.append(120)

    frames.append(overlay_space_indicator(zh_frame, 0, "Back to Chinese").convert("P", palette=Image.ADAPTIVE))
    durations.append(1400)

    GIF_PATH.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        GIF_PATH,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=2,
    )


def main() -> None:
    MARKETING_DIR.mkdir(parents=True, exist_ok=True)
    hero = build_hero()
    hero.save(HERO_PATH, quality=95)
    hero.save(RELEASE_COVER_PATH, quality=95)
    build_demo_gif()
    print(f"Generated {HERO_PATH}")
    print(f"Generated {RELEASE_COVER_PATH}")
    print(f"Generated {GIF_PATH}")


if __name__ == "__main__":
    main()
