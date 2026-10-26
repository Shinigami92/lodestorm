"""Cut the boot screen's emblem (assets/ui/boot/emblem.png) out of its concept image: the crystal in its ring of
storm clouds, cropped around its middle, the black around it made transparent with a soft edge, 512 px. Needs Pillow (e.g. ComfyUI's bundled
Python).

Usage: python assets/ui/boot/source/emblem_build.py
"""

import pathlib

from PIL import Image, ImageDraw, ImageFilter

HERE = pathlib.Path(__file__).parent
# The emblem's middle in the concept and half the crop's size, in its pixels.
CENTER, HALF = (508, 512), 400
# The radius kept (the emblem reaches about 322 from its middle) and how soft its edge is.
RADIUS, SOFTNESS = 385, 12
SIZE = 512


def main() -> None:
    concept = Image.open(HERE / "emblem_concept.png").convert("RGB")
    x, y = CENTER
    crop = concept.crop((x - HALF, y - HALF, x + HALF, y + HALF))
    mask = Image.new("L", crop.size, 0)
    ImageDraw.Draw(mask).ellipse((HALF - RADIUS, HALF - RADIUS, HALF + RADIUS, HALF + RADIUS), fill=255)
    crop.putalpha(mask.filter(ImageFilter.GaussianBlur(SOFTNESS)))
    crop.resize((SIZE, SIZE), Image.LANCZOS).save(HERE.parent / "emblem.png")


if __name__ == "__main__":
    main()
