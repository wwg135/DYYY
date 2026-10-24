#!/usr/bin/env python3
"""用 Pillow 重绘 README 主图，保留旧海报中的七张原始手机截图。

安装依赖：python3 -m pip install Pillow
生成主图：python3 scripts/render_poster.py
字体默认使用 macOS 的苹方 SC 和 Avenir Next，不复制或分发字体文件。
其他系统可通过 --cjk-font / --latin-font 指定本地字体。
"""

from __future__ import annotations

import argparse
import math
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
WIDTH, HEIGHT = 2560, 2368
SCALE = 2
MARGIN, GAP = 112, 24
CARD_WIDTH, CARD_HEIGHT = 566, 824
SOURCE_SIZE = (2368, 2198)
INK = "#F3F5F6"
MUTED = "#A1AAB4"
QUIET = "#697580"
ACCENT = "#7CE5D3"

# 坐标来自旧主图，四周额外保留三个像素用于识别外部黑底。
PHONE_BOXES = (
    (278, 661, 553, 1223),
    (790, 661, 1065, 1223),
    (1302, 661, 1577, 1223),
    (1814, 661, 2089, 1223),
    (278, 1460, 553, 2022),
    (790, 1460, 1065, 2022),
    (1302, 1460, 1577, 2022),
)

PANELS = (
    ("FEED", "视频主界面", ("沉浸式浏览", "功能增强，恰到好处")),
    ("COMMENTS", "毛玻璃评论区", ("半透明材质", "评论与画面，自然相融")),
    ("VIDEO ACTIONS", "视频长按菜单", ("保存 · 解析 · 过滤 · 倍速", "常用操作，触手可及")),
    ("PHOTO ACTIONS", "图文长按菜单", ("一键保存图片、复制链接", "轻松过滤不想看的内容")),
    ("QUICK SETTINGS", "双指快速设置", ("双指长按，快速呼出", "常用开关，一触即达")),
    ("PREFERENCES", "主设置界面", ("分类清晰，随心调整", "备份、恢复与缓存管理")),
    ("ENHANCEMENTS", "增强设置", ("去水印、保存评论内容", "下载反馈，细节更顺手")),
)

FEATURES = (
    ("倍速控制", "默认倍速、长按与手势调速"),
    ("进度显示", "时长、样式、位置与颜色"),
    ("推荐过滤", "直播、热点、HDR、低赞与时长"),
    ("界面净化", "顶栏、底栏、侧栏与元素隐藏"),
    ("长按保存", "视频、封面、音频与图片全选"),
    ("接口解析", "多清晰度选择与批量下载"),
    ("媒体处理", "Live Photo / GIF / WebP / 图集合成"),
    ("工具增强", "毛玻璃、透明度、备份与热更新"),
)


class Poster:
    def __init__(self, cjk_font: Path, latin_font: Path):
        self.cjk_font = cjk_font
        self.latin_font = latin_font
        self.image = self.background()
        self.draw = ImageDraw.Draw(self.image)
        self.phones: list[tuple[Image.Image, tuple[int, int]]] = []

    @staticmethod
    def background() -> Image.Image:
        """低分辨率计算柔和环境光，再放大，避免依赖 NumPy。"""
        small = Image.new("RGB", (320, 296))
        pixels = []
        for y in range(small.height):
            for x in range(small.width):
                teal = math.exp(-((x - 260) / 145) ** 2 - ((y - 18) / 70) ** 2)
                blue = math.exp(-((x - 14) / 120) ** 2 - ((y - 190) / 140) ** 2)
                pixels.append((int(8 + 4 * teal + 2 * blue),
                               int(11 + 13 * teal + 3 * blue),
                               int(15 + 13 * teal + 7 * blue)))
        small.putdata(pixels)
        return small.resize((WIDTH * SCALE, HEIGHT * SCALE), Image.Resampling.BICUBIC).convert("RGBA")

    @lru_cache(maxsize=48)
    def font(self, size: int, role: str = "body") -> ImageFont.FreeTypeFont:
        latin = role.startswith("latin")
        path = self.latin_font if latin else self.cjk_font
        style = {
            "body": "Regular", "medium": "Medium", "title": "Semibold",
            "latin": "Medium", "latin_title": "Demi Bold", "latin_logo": "Heavy",
        }[role]
        preferred = None
        fallback = None
        for index in range(32):
            try:
                font = ImageFont.truetype(str(path), size * SCALE, index=index)
            except OSError:
                break
            family, weight = font.getname()
            if fallback is None:
                fallback = font
            if weight.casefold() == style.casefold():
                preferred = font
                if latin or family.endswith(" SC"):
                    return font
        if preferred or fallback:
            return preferred or fallback
        raise ValueError(f"无法载入字体：{path}")

    def text(self, position, value, size, color=INK, role="body", tracking=0):
        x, y = position
        font = self.font(size, role)
        if tracking == 0:
            self.draw.text((round(x * SCALE), round(y * SCALE)), value, font=font,
                           fill=color, anchor="lt")
            return self.draw.textlength(value, font=font) / SCALE
        cursor = x * SCALE
        baseline = y * SCALE - self.draw.textbbox((0, 0), value, font=font, anchor="ls")[1]
        for character in value:
            self.draw.text((round(cursor), round(baseline)), character,
                           font=font, fill=color, anchor="ls")
            cursor += self.draw.textlength(character, font=font) + tracking * SCALE
        return (cursor - x * SCALE) / SCALE - tracking

    def line(self, box, color, width=1):
        self.draw.line(tuple(round(v * SCALE) for v in box), fill=color, width=round(width * SCALE))

    def rounded(self, box, radius, fill, outline=None, width=1):
        self.draw.rounded_rectangle(tuple(round(v * SCALE) for v in box), radius=radius * SCALE,
                                    fill=fill, outline=outline, width=round(width * SCALE))

    def chip(self, x, y, value, latin=False):
        role = "latin" if latin else "medium"
        size = 23
        width = self.draw.textlength(value, font=self.font(size, role)) / SCALE + 36
        self.rounded((x, y, x + width, y + 48), 24, "#17252A", "#2A3B40")
        self.text((x + 18, y + 12), value, size, "#B8D2D0", role)
        return x + width + 12

    def header(self):
        self.text((MARGIN + 2, 83), "DOUYIN, YOUR WAY.", 23, ACCENT, "latin_title", tracking=3.4)
        self.text((MARGIN - 8, 136), "DYYY", 216, INK, "latin_logo", tracking=-9)
        self.line((MARGIN + 2, 365, MARGIN + 62, 365), ACCENT, 3)
        self.text((MARGIN + 82, 348), "抖音 UI 定制与功能增强", 30, INK, "medium")
        self.text((MARGIN + 2, 407), "来自 Huami · 维他入我心", 26, MUTED)

        self.text((1288, 158), "让抖音，更合你意。", 77, INK, "title")
        self.text((1292, 270), "界面简一点，操作顺一点。", 32, MUTED)
        next_x = self.chip(1292, 371, "iOS 14.0+", latin=True)
        next_x = self.chip(next_x, 371, "抖音 36.5.0 测试")
        self.chip(next_x, 371, "Theos / Logos", latin=True)

    def panel(self, x, y, index, category, title, descriptions):
        self.rounded((x, y, x + CARD_WIDTH, y + CARD_HEIGHT), 30, "#12181F", "#29313A")
        self.line((x + 36, y + 67, x + CARD_WIDTH - 36, y + 67), "#28323A")
        self.text((x + 36, y + 31), category, 21, MUTED, "latin_title", tracking=1.5)
        self.text((x + CARD_WIDTH - 65, y + 30), f"{index:02d}", 22, ACCENT, "latin")
        self.text((x + 36, y + 94), title, 46, INK, "title")
        for line_index, value in enumerate(descriptions):
            self.text((x + 38, y + 162 + line_index * 37), value, 27, MUTED)

    @staticmethod
    def extract_phone(source: Image.Image, box) -> Image.Image:
        """仅移除连通至边缘的黑底，手机内部与截图像素保持原样。"""
        phone = source.crop(box).convert("RGBA")
        boundary = phone.convert("RGB").point(lambda value: 255 if value > 8 else 0)
        red, green, blue = boundary.split()
        boundary = ImageChops.lighter(ImageChops.lighter(red, green), blue)
        for seed in ((0, 0), (phone.width - 1, 0),
                     (0, phone.height - 1), (phone.width - 1, phone.height - 1)):
            if boundary.getpixel(seed) == 0:
                ImageDraw.floodfill(boundary, seed, 128)
        phone.putalpha(boundary.point(lambda value: 0 if value == 128 else 255))
        return phone

    def screenshot(self, source, index, x, y):
        phone = self.extract_phone(source, PHONE_BOXES[index])
        position = (x + (CARD_WIDTH - phone.width) // 2, y + 234)

        # 阴影参与超采样；手机最后以原始尺寸合成，避免二次缩放模糊截图。
        shadow = Image.new("RGBA", self.image.size)
        mask = phone.getchannel("A").resize((phone.width * SCALE, phone.height * SCALE),
                                           Image.Resampling.LANCZOS)
        shadow.paste((0, 0, 0, 145), (position[0] * SCALE, (position[1] + 14) * SCALE), mask)
        self.image = Image.alpha_composite(self.image, shadow.filter(ImageFilter.GaussianBlur(15 * SCALE)))
        self.draw = ImageDraw.Draw(self.image)
        self.phones.append((phone, position))

    def more(self, x, y):
        self.panel(x, y, 8, "AND MUCH MORE", "更多功能，随你设定", ())
        for index, (title, detail) in enumerate(FEATURES):
            top = y + 170 + index * 76
            self.rounded((x + 37, top + 7, x + 42, top + 12), 2, ACCENT)
            self.text((x + 57, top), title, 29, INK, "medium")
            self.text((x + 57, top + 39), detail, 23, MUTED)

    def footer(self):
        self.line((MARGIN, 2224, WIDTH - MARGIN, 2224), "#2A353E")
        self.text((MARGIN, 2264), "github.com/Wtrwx/DYYY", 27, "#D0D7DC", "latin")
        value = "仅供学习交流 · 禁止用于商业用途"
        width = self.draw.textlength(value, font=self.font(24)) / SCALE
        self.text((WIDTH - MARGIN - width, 2268), value, 24, QUIET)

    def render(self, source: Image.Image) -> Image.Image:
        if source.size != SOURCE_SIZE:
            raise ValueError(f"旧海报尺寸应为 {SOURCE_SIZE}，实际为 {source.size}")
        self.header()
        for index, (category, title, descriptions) in enumerate(PANELS):
            x = MARGIN + (index % 4) * (CARD_WIDTH + GAP)
            y = 496 + (index // 4) * (CARD_HEIGHT + GAP)
            self.panel(x, y, index + 1, category, title, descriptions)
            self.screenshot(source, index, x, y)
        self.more(MARGIN + 3 * (CARD_WIDTH + GAP), 1344)
        self.footer()
        result = self.image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
        for phone, position in self.phones:
            result.alpha_composite(phone, position)
        return result.convert("RGB")


def default_font(latin=False) -> Path:
    if latin:
        candidates = [Path("/System/Library/Fonts/Avenir Next.ttc")]
    else:
        candidates = [Path("/System/Library/Fonts/PingFang.ttc")]
        candidates += sorted(Path("/System/Library/AssetsV2").glob(
            "com_apple_MobileAsset_Font*/*/AssetData/PingFang.ttc"))
    for path in candidates:
        if path.is_file():
            return path
    option = "--latin-font" if latin else "--cjk-font"
    raise FileNotFoundError(f"没有找到默认字体，请使用 {option} 指定字体文件")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Screenshots/source/DYYY_poster_original.png")
    parser.add_argument("--output", type=Path, default=ROOT / "Screenshots/DYYY_poster.png")
    parser.add_argument("--cjk-font", type=Path)
    parser.add_argument("--latin-font", type=Path)
    args = parser.parse_args()
    if args.source.resolve() == args.output.resolve():
        parser.error("原始海报和输出主图不能使用同一个文件")
    poster = Poster(args.cjk_font or default_font(), args.latin_font or default_font(latin=True))
    with Image.open(args.source) as source:
        result = poster.render(source)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output, optimize=True)
    print(f"已生成：{args.output}（{result.width} × {result.height}）")
    print(f"中文字体：{poster.font(27).getname()}；标题字体：{poster.font(46, 'title').getname()}")
    print(f"英文字体：{poster.font(216, 'latin_logo').getname()}；保留原始截图：{len(poster.phones)} 张")


if __name__ == "__main__":
    main()
