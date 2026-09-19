"""Image augmentations for rendered pump glyphs and rows.

Every augmentation is applied with a sampled probability and strength, all drawn
from the passed ``rng`` so a run is reproducible under a seed. ``augment`` is the
single pipeline entry point; it applies the operations in a fixed order and
returns the perspective homography when perspective fired, so the row renderer
can transform its glyph boxes into the warped image.
"""

from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from .profiles import MakeProfile

# Default per-operation probabilities (overridable per call).
DEFAULT_PROBS: dict[str, float] = {
    "perspective": 0.6,
    "ghosting": 0.5,
    "blur": 0.6,
    "glare": 0.5,
    "canopy": 0.4,
    "reflection": 0.4,
    "contrast_collapse": 0.15,
    "noise_exposure": 0.7,
    "occlusion": 0.3,
}


def homography_from_corners(src: np.ndarray, dst: np.ndarray) -> np.ndarray:
    """Solve the 3x3 homography mapping four ``src`` corners to ``dst`` (DLT)."""
    a = []
    for (x, y), (u, v) in zip(src, dst):
        a.append([-x, -y, -1.0, 0.0, 0.0, 0.0, u * x, u * y, u])
        a.append([0.0, 0.0, 0.0, -x, -y, -1.0, v * x, v * y, v])
    a = np.asarray(a, dtype=np.float64)
    _, _, vt = np.linalg.svd(a)
    hmat = vt[-1].reshape(3, 3)
    return hmat / hmat[2, 2]


def random_homography(
    rng: np.random.Generator, w: int, h: int, max_tilt_deg: float = 12.0
) -> np.ndarray:
    """A mild perspective warp within +-max_tilt_deg, as a 3x3 pixel-space homography.

    Each canvas corner is displaced by at most ``tan(max_tilt) * min(w,h) / 2``
    pixels and the homography is the exact mapping between the four corner
    pairs, so the warp stays centred and mild on any canvas size.
    """
    src = np.array([[0, 0], [w, 0], [w, h], [0, h]], dtype=np.float64)
    amp = float(np.tan(np.deg2rad(max_tilt_deg)) * 0.5 * min(w, h))
    dst = src + rng.uniform(-amp, amp, size=(4, 2))
    return homography_from_corners(src, dst)


def _bilinear(img: np.ndarray, sx: np.ndarray, sy: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    x0 = np.floor(sx).astype(np.int32)
    y0 = np.floor(sy).astype(np.int32)
    fx = (sx - x0)[..., None].astype(np.float32)
    fy = (sy - y0)[..., None].astype(np.float32)
    x1 = x0 + 1
    y1 = y0 + 1
    valid = (x0 >= 0) & (x1 < w) & (y0 >= 0) & (y1 < h)
    x0c = np.clip(x0, 0, w - 1)
    x1c = np.clip(x1, 0, w - 1)
    y0c = np.clip(y0, 0, h - 1)
    y1c = np.clip(y1, 0, h - 1)
    i00 = img[y0c, x0c].astype(np.float32)
    i01 = img[y0c, x1c].astype(np.float32)
    i10 = img[y1c, x0c].astype(np.float32)
    i11 = img[y1c, x1c].astype(np.float32)
    out = i00 * (1 - fx) * (1 - fy) + i01 * fx * (1 - fy) + i10 * (1 - fx) * fy + i11 * fx * fy
    out = out.astype(np.float32)
    out[~valid] = 0.0
    return out


def warp_perspective(img: np.ndarray, hmat: np.ndarray) -> np.ndarray:
    """Inverse-map ``img`` through ``hmat``, cropping back to the input size."""
    h, w = img.shape[:2]
    hinv = np.linalg.inv(hmat)
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    sx = hinv[0, 0] * xs + hinv[0, 1] * ys + hinv[0, 2]
    sy = hinv[1, 0] * xs + hinv[1, 1] * ys + hinv[1, 2]
    sw = hinv[2, 0] * xs + hinv[2, 1] * ys + hinv[2, 2]
    return _bilinear(img, sx / sw, sy / sw)


def apply_perspective(img: np.ndarray, rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    h, w = img.shape[:2]
    hmat = random_homography(rng, w, h)
    return warp_perspective(img, hmat), hmat


def apply_lcd_ghosting(
    img: np.ndarray, ghost_mask: np.ndarray, profile: MakeProfile, rng: np.random.Generator
) -> np.ndarray:
    """Strengthen the faint off-segment ghosts (lcd only)."""
    if ghost_mask is None:
        return img
    strength = float(rng.uniform(0.1, 0.5))
    on = np.asarray(profile.on_color.midpoint(), dtype=np.float32)
    g = ghost_mask[..., None].astype(np.float32)
    return img + g * (on - img) * strength


def apply_blur(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    pil = Image.fromarray(img.astype(np.uint8))
    if rng.random() < 0.6:
        pil = pil.filter(ImageFilter.GaussianBlur(float(rng.uniform(0.5, 1.5))))
    if rng.random() < 0.35:
        k = 3 if rng.random() < 0.5 else 5
        kernel = np.zeros((k, k), dtype=np.float32)
        kernel[k // 2, :] = 1.0 / k
        pil = pil.filter(ImageFilter.Kernel((k, k), kernel.ravel().tolist(), 1, 0))
    return np.asarray(pil, dtype=np.float32)


def apply_glare(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    h, w = img.shape[:2]
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    if rng.random() < 0.5:
        cx, cy = float(rng.uniform(0.1, 0.9)) * w, float(rng.uniform(0.1, 0.9)) * h
        rx, ry = float(rng.uniform(0.2, 0.6)) * w, float(rng.uniform(0.2, 0.6)) * h
        d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    else:
        d.line([(-w, h * 0.35), (2 * w, h * 0.65)], fill=255, width=int(rng.integers(4, 12)))
    mask = mask.filter(ImageFilter.GaussianBlur(float(rng.uniform(4, 10))))
    strength = float(rng.uniform(0.3, 0.7))
    m = (np.asarray(mask, dtype=np.float32) / 255.0)[..., None]
    return img + m * (255.0 - img) * strength


def apply_canopy(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    h, w = img.shape[:2]
    if rng.random() < 0.5:
        grad = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :, None]
    else:
        grad = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None, None]
    amount = float(rng.uniform(0.05, 0.25))
    img = img * (1.0 - amount) + img * grad * amount
    if rng.random() < 0.7:
        mask = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(mask)
        x0 = float(rng.uniform(0.1, 0.5)) * w
        y0 = float(rng.uniform(0.1, 0.5)) * h
        d.rectangle([x0, y0, x0 + 0.4 * w, y0 + 0.3 * h], fill=int(rng.integers(30, 70)))
        mask = mask.filter(ImageFilter.GaussianBlur(float(rng.uniform(6, 14))))
        m = (np.asarray(mask, dtype=np.float32) / 255.0)[..., None]
        img = img + m * (255.0 - img) * float(rng.uniform(0.05, 0.2))
    return img


def apply_reflection(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """A broad, soft reflection blob over up to half the cell (gap 3).

    Lower frequency than ``apply_glare``: one large gaussian with a wide blur and
    moderate strength, so the reflection-heavy Scheidt heads on the held-out sheet
    are represented without a specular hotspot.
    """
    h, w = img.shape[:2]
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    cx = float(rng.uniform(0.1, 0.9)) * w
    cy = float(rng.uniform(0.1, 0.9)) * h
    rx = float(rng.uniform(0.2, 0.5)) * w
    ry = float(rng.uniform(0.2, 0.5)) * h
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(float(rng.uniform(8, 16))))
    strength = float(rng.uniform(0.15, 0.4))
    m = (np.asarray(mask, dtype=np.float32) / 255.0)[..., None]
    return img + m * (255.0 - img) * strength


def apply_contrast_collapse(
    img: np.ndarray, profile: MakeProfile, rng: np.random.Generator
) -> np.ndarray:
    """Collapse the on/ground contrast toward the ground colour (gap 3).

    Every pixel moves toward the profile's ground colour until the on/ground
    difference is ``target`` (10-25%) of the original. The faint boards on the
    held-out sheet (pump-004, pump-062) sit at 10-20% contrast, while the
    renderer never drew below ~50%; this is what closes that gap.
    """
    ground = np.asarray(profile.ground_color.midpoint(), dtype=np.float32)
    target = float(rng.uniform(0.10, 0.25))
    return img + (ground - img) * (1.0 - target)


def apply_noise_exposure(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    if rng.random() < 0.7:
        img = img + rng.normal(0.0, float(rng.uniform(2, 10)), img.shape).astype(np.float32)
    img = np.clip(img, 0.0, 255.0)
    if rng.random() < 0.6:
        gamma = float(rng.uniform(0.7, 1.4))
        img = np.power(img / 255.0, gamma) * 255.0
    if rng.random() < 0.5:
        c = float(rng.uniform(0.8, 1.2))
        img = (img - 128.0) * c + 128.0
    return img


def apply_occlusion(img: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    h, w = img.shape[:2]
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    x0 = float(rng.uniform(-0.3, 0.3)) * w
    y0 = float(rng.uniform(-0.3, 1.3)) * h
    x1 = float(rng.uniform(0.7, 1.3)) * w
    y1 = float(rng.uniform(-0.3, 1.3)) * h
    d.line([x0, y0, x1, y1], fill=255, width=int(rng.integers(2, 7)))
    mask = mask.filter(ImageFilter.GaussianBlur(0.5))
    m = (np.asarray(mask, dtype=np.float32) / 255.0)[..., None]
    dark = float(rng.uniform(0.0, 0.3))
    return img * (1.0 - m) + m * (img * dark)


def augment(
    image: np.ndarray,
    profile: MakeProfile,
    rng: np.random.Generator,
    overrides: dict[str, float] | None = None,
    ghost_mask: np.ndarray | None = None,
) -> tuple[np.ndarray, np.ndarray | None]:
    """Apply the augmentation pipeline to a uint8 HxWx3 image.

    Returns ``(augmented, homography)``; ``homography`` is non-None only when
    perspective fired (so callers can warp their boxes the same way).
    """
    overrides = overrides or {}

    def prob(name: str) -> float:
        return overrides.get(name, DEFAULT_PROBS[name])

    img = image.astype(np.float32)
    hmat = None
    if rng.random() < prob("perspective"):
        img, hmat = apply_perspective(img, rng)
    if profile.technology == "lcd" and rng.random() < prob("ghosting"):
        img = apply_lcd_ghosting(img, ghost_mask, profile, rng)
    if rng.random() < prob("blur"):
        img = apply_blur(img, rng)
    if rng.random() < prob("glare"):
        img = apply_glare(img, rng)
    if rng.random() < prob("canopy"):
        img = apply_canopy(img, rng)
    if rng.random() < prob("reflection"):
        img = apply_reflection(img, rng)
    if rng.random() < prob("contrast_collapse"):
        img = apply_contrast_collapse(img, profile, rng)
    if rng.random() < prob("noise_exposure"):
        img = apply_noise_exposure(img, rng)
    if rng.random() < prob("occlusion"):
        img = apply_occlusion(img, rng)
    return np.clip(img, 0, 255).astype(np.uint8), hmat
