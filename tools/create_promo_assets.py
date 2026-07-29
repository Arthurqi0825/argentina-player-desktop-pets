from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT / "media"
ASSETS = ROOT / "assets"
BACKGROUND_PATH = MEDIA / "promo-background-source.png"

CELL_W = 192
CELL_H = 208
FRAME_COUNTS = {0: 6, 1: 8, 2: 8, 3: 4, 4: 5, 7: 6}

PLAYER_FILES = [
    ("Messi", "messi.png"),
    ("Enzo", "enzo.png"),
    ("Romero", "romero.png"),
    ("Lisandro", "lisandro.png"),
    ("Paredes", "paredes.png"),
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc" if bold else r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\segoeuib.ttf" if bold else r"C:\Windows\Fonts\segoeui.ttf"),
        Path(r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default()


def cover_background(size: tuple[int, int]) -> Image.Image:
    source = Image.open(BACKGROUND_PATH).convert("RGB")
    return ImageOps.fit(source, size, method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))


def extract_frame(atlas: Image.Image, row: int, column: int, size: tuple[int, int]) -> Image.Image:
    column %= FRAME_COUNTS.get(row, 8)
    frame = atlas.crop((column * CELL_W, row * CELL_H, (column + 1) * CELL_W, (row + 1) * CELL_H))
    return frame.resize(size, Image.Resampling.LANCZOS)


def paste_with_shadow(base: Image.Image, sprite: Image.Image, xy: tuple[int, int], blur: int = 8) -> None:
    shadow = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
    alpha = sprite.getchannel("A").filter(ImageFilter.GaussianBlur(blur))
    shadow.putalpha(alpha.point(lambda value: int(value * 0.42)))
    black = Image.new("RGBA", sprite.size, (0, 0, 0, 255))
    shadow = Image.composite(black, shadow, shadow)
    base.alpha_composite(shadow, (xy[0] + 5, xy[1] + 9))
    base.alpha_composite(sprite, xy)


def rounded_panel(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, radius=18, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def make_social_preview(atlases: dict[str, Image.Image]) -> Path:
    canvas = cover_background((1280, 640)).convert("RGBA")
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    for x in range(0, 730):
        alpha = int(176 * (1 - x / 730))
        overlay_draw.line((x, 0, x, 640), fill=(3, 15, 48, alpha))
    canvas.alpha_composite(overlay)

    draw = ImageDraw.Draw(canvas)
    title_font = font(55, bold=True)
    subtitle_font = font(24)
    badge_font = font(19, bold=True)
    footer_font = font(16)

    draw.text((58, 58), "ARGENTINA PLAYER", font=title_font, fill=(255, 255, 255))
    draw.text((58, 120), "DESKTOP PETS", font=title_font, fill=(255, 255, 255))
    draw.text(
        (61, 199),
        "Five animated companions for Windows",
        font=subtitle_font,
        fill=(194, 231, 255),
    )

    badges = [
        ("中文 / Español", 61, 252, 184),
        ("Manual control", 257, 252, 170),
        ("Collision avoidance", 439, 252, 214),
    ]
    for text, x, y, width in badges:
        rounded_panel(draw, (x, y, x + width, y + 42), (18, 96, 169, 210), (151, 224, 255, 220), 21, 1)
        draw.text((x + width / 2, y + 21), text, font=badge_font, fill="white", anchor="mm")

    sprite_size = (154, 167)
    x_positions = [505, 654, 803, 952, 1101]
    y_positions = [377, 391, 369, 388, 374]
    for index, (name, _) in enumerate(PLAYER_FILES):
        sprite = extract_frame(atlases[name], 3, 1 + index % 2, sprite_size)
        paste_with_shadow(canvas, sprite, (x_positions[index], y_positions[index]), blur=7)
        draw.text(
            (x_positions[index] + sprite_size[0] // 2, 566),
            name,
            font=font(17, bold=True),
            fill=(236, 249, 255),
            anchor="mm",
        )

    rounded_panel(draw, (58, 534, 458, 584), (4, 23, 64, 190), (103, 194, 245, 180), 12, 1)
    draw.text((76, 550), "Lightweight C# desktop overlay", font=badge_font, fill=(255, 255, 255))
    draw.text(
        (62, 612),
        "Unofficial • Non-commercial • Fan-made",
        font=footer_font,
        fill=(188, 225, 248),
        anchor="lm",
    )

    output = MEDIA / "social-preview-1280x640.jpg"
    quality = 91
    while quality >= 72:
        canvas.convert("RGB").save(output, "JPEG", quality=quality, optimize=True, progressive=True)
        if output.stat().st_size < 1_000_000:
            break
        quality -= 3
    return output


def draw_mock_window(draw: ImageDraw.ImageDraw, box, title: str, active: bool = False) -> None:
    x1, y1, x2, y2 = box
    outline = (113, 214, 255, 230) if active else (107, 179, 224, 150)
    rounded_panel(draw, box, (6, 29, 73, 165), outline, 15, 2)
    draw.rounded_rectangle((x1 + 1, y1 + 1, x2 - 1, y1 + 38), radius=14, fill=(16, 72, 128, 205))
    draw.rectangle((x1 + 1, y1 + 23, x2 - 1, y1 + 39), fill=(16, 72, 128, 205))
    draw.text((x1 + 16, y1 + 18), title, font=font(15, bold=True), fill=(221, 245, 255), anchor="lm")
    for index in range(3):
        cx = x2 - 62 + index * 18
        draw.ellipse((cx, y1 + 14, cx + 7, y1 + 21), fill=(143, 221, 255, 200))
    draw.rounded_rectangle((x1 + 18, y1 + 59, x2 - 18, y2 - 22), radius=10, fill=(49, 126, 180, 74))


def pet_position(name: str, t: float) -> tuple[float, float, float]:
    if name == "Messi":
        if t < 5.6:
            x = 45 + 65 * t
            direction = 1
        else:
            x = 409 - 49 * (t - 5.6)
            direction = -1
        return x, 345 + 12 * math.sin(t * 2.3), direction
    if name == "Enzo":
        phase = (t * 66) % 780
        direction = 1 if phase < 390 else -1
        x = 80 + (phase if phase < 390 else 780 - phase)
        return x, 115 + 23 * math.sin(t * 1.7 + 0.8), direction
    if name == "Romero":
        return 460 + 22 * math.sin(t * 1.1), 326 + 17 * math.sin(t * 2.1), -1
    if name == "Lisandro":
        phase = (t * 54 + 160) % 640
        direction = -1 if phase < 320 else 1
        x = 670 - (phase if phase < 320 else 640 - phase)
        return x, 172 + 25 * math.cos(t * 1.5), direction
    phase = (t * 58 + 90) % 690
    direction = -1 if phase < 345 else 1
    x = 760 - (phase if phase < 345 else 690 - phase)
    return x, 385 + 14 * math.sin(t * 1.9 + 2.0), direction


def speech_bubble(canvas: Image.Image, center: tuple[int, int], text: str) -> None:
    draw = ImageDraw.Draw(canvas)
    text_font = font(21, bold=True)
    left = max(18, min(center[0] - 120, canvas.width - 258))
    top = max(68, center[1] - 78)
    box = (left, top, left + 240, top + 54)
    rounded_panel(draw, box, (255, 255, 255, 245), (15, 34, 55, 255), 27, 2)
    tail = [(center[0] - 8, top + 48), (center[0] + 10, top + 48), (center[0], center[1] - 5)]
    draw.polygon(tail, fill=(255, 255, 255, 245))
    draw.line(tail + [tail[0]], fill=(15, 34, 55, 255), width=2)
    draw.text((left + 120, top + 27), text, font=text_font, fill=(13, 30, 51), anchor="mm")


def make_demo_gif(atlases: dict[str, Image.Image]) -> tuple[Path, Path]:
    width, height = 960, 540
    fps = 8
    duration = 10
    base_background = cover_background((width, height)).convert("RGBA")
    frames: list[Image.Image] = []
    sprite_size = (124, 134)

    for frame_index in range(fps * duration):
        t = frame_index / fps
        canvas = base_background.copy()
        tint = Image.new("RGBA", canvas.size, (0, 7, 25, 42))
        canvas.alpha_composite(tint)
        draw = ImageDraw.Draw(canvas)

        rounded_panel(draw, (22, 18, 586, 64), (3, 19, 55, 205), (109, 203, 247, 155), 18, 1)
        draw.text((43, 41), "FIVE PETS • ONE WINDOWS OVERLAY", font=font(23, bold=True), fill="white", anchor="lm")

        draw_mock_window(draw, (585, 92, 925, 275), "Window obstacle", active=2.0 < t < 4.5)
        draw_mock_window(draw, (32, 238, 302, 430), "Desktop workspace", active=7.0 < t < 9.5)

        language_spanish = t >= 5.0
        rounded_panel(draw, (695, 20, 934, 67), (4, 27, 70, 220), (118, 209, 250, 180), 18, 1)
        draw.text((716, 43), "Language", font=font(16, bold=True), fill=(196, 231, 250), anchor="lm")
        language_text = "Español" if language_spanish else "中文"
        draw.text((909, 43), language_text, font=font(18, bold=True), fill="white", anchor="rm")

        positions: dict[str, tuple[int, int]] = {}
        for player_index, (name, _) in enumerate(PLAYER_FILES):
            x_float, y_float, direction = pet_position(name, t)
            x = int(max(0, min(x_float, width - sprite_size[0])))
            y = int(max(72, min(y_float, height - sprite_size[1] - 12)))
            row = 1 if direction >= 0 else 2
            animation_column = (frame_index + player_index * 2) % 8
            sprite = extract_frame(atlases[name], row, animation_column, sprite_size)
            paste_with_shadow(canvas, sprite, (x, y), blur=6)
            positions[name] = (x + sprite_size[0] // 2, y)

            label_width = 88 if name != "Lisandro" else 102
            rounded_panel(
                draw,
                (x + sprite_size[0] // 2 - label_width // 2, y + sprite_size[1] - 5,
                 x + sprite_size[0] // 2 + label_width // 2, y + sprite_size[1] + 20),
                (4, 29, 72, 205),
                None,
                10,
            )
            draw.text(
                (x + sprite_size[0] // 2, y + sprite_size[1] + 7),
                name,
                font=font(14, bold=True),
                fill=(235, 249, 255),
                anchor="mm",
            )

        if 3.0 <= t < 4.45:
            speech_bubble(canvas, positions["Messi"], "给你俩窝窝")
        elif 6.2 <= t < 7.9:
            speech_bubble(canvas, positions["Messi"], "¿Qué mirás, bobo?")

        if 8.0 <= t < 9.7:
            rounded_panel(draw, (614, 376, 930, 506), (5, 27, 67, 225), (113, 212, 255, 210), 16, 2)
            draw.text((635, 398), "Manual Controller", font=font(18, bold=True), fill="white")
            draw.text((635, 428), "Selected: Messi", font=font(15), fill=(199, 235, 253))
            for label, bx, by in [("▲", 802, 417), ("◀", 763, 454), ("■", 802, 454), ("▶", 841, 454), ("▼", 802, 491)]:
                rounded_panel(draw, (bx, by, bx + 34, by + 30), (31, 111, 173, 230), (145, 225, 255, 210), 7, 1)
                draw.text((bx + 17, by + 15), label, font=font(15, bold=True), fill="white", anchor="mm")

        draw.text(
            (24, 520),
            "Unofficial • Non-commercial • Fan-made demo",
            font=font(14),
            fill=(205, 236, 252),
            anchor="lm",
        )
        frames.append(canvas.convert("RGB"))

    gif_path = MEDIA / "desktop-pets-demo.gif"
    palette_frames = [frame.quantize(colors=96, method=Image.Quantize.MEDIANCUT) for frame in frames]
    palette_frames[0].save(
        gif_path,
        save_all=True,
        append_images=palette_frames[1:],
        duration=int(1000 / fps),
        loop=0,
        optimize=True,
        disposal=2,
    )

    sheet = Image.new("RGB", (960, 540 * 4), "white")
    for sheet_index, source_index in enumerate([0, 27, 51, 70]):
        sheet.paste(frames[source_index], (0, sheet_index * 540))
    sheet_path = MEDIA / "demo-contact-sheet.jpg"
    sheet.save(sheet_path, "JPEG", quality=88, optimize=True)
    return gif_path, sheet_path


def main() -> None:
    MEDIA.mkdir(parents=True, exist_ok=True)
    atlases = {
        name: Image.open(ASSETS / filename).convert("RGBA")
        for name, filename in PLAYER_FILES
    }
    social_path = make_social_preview(atlases)
    gif_path, sheet_path = make_demo_gif(atlases)
    print(f"social={social_path} bytes={social_path.stat().st_size}")
    print(f"gif={gif_path} bytes={gif_path.stat().st_size}")
    print(f"sheet={sheet_path} bytes={sheet_path.stat().st_size}")


if __name__ == "__main__":
    main()
