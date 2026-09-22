"""PU.66: a turned training copy carries its boxes with the pixels."""
from PIL import Image, ImageDraw

from pump_reader.detdata import rotated_quads


def _white_bbox(im):
    return im.convert("L").point(lambda v: 255 if v > 128 else 0).getbbox()


def test_turned_box_lands_on_the_turned_pixels():
    w, h = 400, 300
    quad = [[0.30, 0.40], [0.70, 0.40], [0.70, 0.55], [0.30, 0.55]]
    for angle in (-25, -8, 8, 15, 25):
        im = Image.new("RGB", (w, h))
        ImageDraw.Draw(im).polygon([(x * w, y * h) for x, y in quad], fill=(255, 255, 255))
        turned = im.rotate(angle, expand=True, resample=Image.BICUBIC, fillcolor=(0, 0, 0))
        moved = rotated_quads([quad], w, h, angle, turned.size)[0]
        xs = [x * turned.width for x, _ in moved]
        ys = [y * turned.height for _, y in moved]
        x0, y0, x1, y1 = _white_bbox(turned)
        # The quad's upright bounds match the white shape's to a pixel or two.
        assert abs(min(xs) - x0) <= 2 and abs(max(xs) - x1) <= 2, angle
        assert abs(min(ys) - y0) <= 2 and abs(max(ys) - y1) <= 2, angle


def test_the_sign_is_pinned():
    # A counter-clockwise turn lifts a point right of the centre.
    moved = rotated_quads([[[0.9, 0.5]] * 4], 100, 100, 30, (100, 100))[0][0]
    assert moved[1] < 0.5 and moved[0] < 0.9
