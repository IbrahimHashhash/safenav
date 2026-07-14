"""
models/sam_ground_segmenter.py
==============================
SAM 2.1 ground / floor segmentation for the SafeNav pipeline.

The forward-facing, chest/head-height camera sees a large floor region in the
lower part of every frame. Because the floor is physically close to the camera
it produces *small* metric-depth values that the navigation logic would
otherwise mistake for obstacles. This module segments that floor with SAM 2.1
using fixed bottom-centre positive point prompts and returns a boolean ground
mask, so the depth map can be zeroed there before obstacle analysis.

Design / performance notes (see inline comments for detail):
  * The SAM 2.1 model + predictor are built ONCE in ``__init__`` and reused for
    every frame -- the image encoder is the expensive part; the point decode is
    cheap. This is the single most important real-time optimisation.
  * All inference runs under ``torch.inference_mode()`` + CUDA fp16 autocast.
  * The heavy ``sam2`` import is deferred into ``__init__`` so this module is
    importable even when the package/checkpoint is absent (mirrors the lazy
    model loading in ``api.server._load_models``).
"""
from __future__ import annotations

import contextlib
import logging
import os

import cv2
import numpy as np
import torch

# child of the "safenav" logger configured in api.server -> inherits its
# file + console handlers via propagation.
logger = logging.getLogger("safenav.sam")

# variant -> (hydra config shipped with the `sam2` package, checkpoint filename)
_VARIANTS = {
    "tiny":      ("configs/sam2.1/sam2.1_hiera_t.yaml",  "sam2.1_hiera_tiny.pt"),
    "small":     ("configs/sam2.1/sam2.1_hiera_s.yaml",  "sam2.1_hiera_small.pt"),
    "base_plus": ("configs/sam2.1/sam2.1_hiera_b+.yaml", "sam2.1_hiera_base_plus.pt"),
    "large":     ("configs/sam2.1/sam2.1_hiera_l.yaml",  "sam2.1_hiera_large.pt"),
}

# Positive prompts as (width_frac, height_frac). They sit LOW and spread wide
# (mirroring the validated Colab prompts) so they land on the walkable floor and
# not on a person/object standing in the centre of the frame.
_PROMPT_FRACS = ((0.50, 0.92), (0.25, 0.92), (0.75, 0.92), (0.50, 0.97))

_MAX_GROUND_FRAC = 0.80    # reject masks covering more of the frame than this
_LOWER_BAND_FRAC = 0.40    # ground may only live in the lower 60% (rows >= 0.4H)
_MIN_REGION_FRAC = 0.005   # drop connected components smaller than 0.5% of frame
_BOTTOM_TOUCH_FRAC = 0.10  # "touches bottom" = has pixels in the bottom 10% rows
                           # (SAM floor masks often stop a few px short of the
                           #  literal last row, so testing only row H-1 is too
                           #  brittle and was discarding valid floors).


class SAMGroundSegmenter:
    """Loads SAM 2.1 once and turns BGR frames into boolean ground masks."""

    def __init__(self, variant: str = "small", device: str | None = None,
                 checkpoint: str | None = None, model_cfg: str | None = None):
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")
        cfg, ckpt_name = _VARIANTS[variant]
        model_cfg = model_cfg or cfg
        checkpoint = checkpoint or os.path.join("checkpoints", ckpt_name)

        # Deferred import keeps this module importable without sam2 installed.
        from sam2.build_sam import build_sam2
        from sam2.sam2_image_predictor import SAM2ImagePredictor

        if self.device == "cuda":
            # harmless on Volta, a speed-up on Ampere+; cudnn benchmark picks
            # the fastest conv algos for our fixed frame size.
            torch.backends.cuda.matmul.allow_tf32 = True
            torch.backends.cudnn.allow_tf32 = True
            torch.backends.cudnn.benchmark = True

        # Built ONCE and reused for every frame (predictor object is stateful:
        # set_image() runs the encoder, predict() reuses those embeddings).
        model = build_sam2(model_cfg, checkpoint, device=self.device)
        self.predictor = SAM2ImagePredictor(model)
        logger.info("SAM 2.1 ground segmenter ready (variant=%s, device=%s, ckpt=%s)",
                    variant, self.device, checkpoint)

    def _autocast(self):
        # bf16 autocast on GPU only (matches the validated Colab run; works on
        # Volta+ and is numerically steadier than fp16 for the mask logits).
        # CPU autocast would only slow this down, so skip it.
        if self.device == "cuda":
            return torch.autocast("cuda", dtype=torch.bfloat16)
        return contextlib.nullcontext()

    def get_ground_mask(self, frame: np.ndarray) -> np.ndarray:
        """BGR frame -> boolean ``(H, W)`` ground mask (True = ground pixel)."""
        h, w = frame.shape[:2]
        # SAM expects an RGB HWC uint8 image; this cvtColor is the only copy.
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        points = np.array([[wf * w, hf * h] for wf, hf in _PROMPT_FRACS],
                          dtype=np.float32)             # (x, y) pixel coords
        labels = np.ones(len(points), dtype=np.int32)   # all positive prompts

        # Encode the image once, then decode the cheap point prompts. multimask
        # gives 3 candidate masks (different floor extents); scores rank them.
        with torch.inference_mode(), self._autocast():
            self.predictor.set_image(rgb)
            masks, scores, _ = self.predictor.predict(
                point_coords=points, point_labels=labels, multimask_output=True,
            )

        mask = self._select_floor_mask(masks, scores, h, w)
        logger.info("Ground mask covers %.1f%% of image", 100.0 * float(mask.mean()))
        return mask

    @staticmethod
    def _largest_component(mask: np.ndarray) -> np.ndarray:
        """Keep only the largest connected blob of a boolean mask."""
        n, labels = cv2.connectedComponents(mask.astype(np.uint8))
        if n <= 1:
            return mask
        counts = np.bincount(labels.ravel())
        counts[0] = 0                       # ignore background label
        return labels == int(counts.argmax())

    @staticmethod
    def _remove_small(mask: np.ndarray, h: int, w: int) -> np.ndarray:
        """Drop connected components smaller than _MIN_REGION_FRAC of the frame."""
        n, labels, stats, _ = cv2.connectedComponentsWithStats(mask.astype(np.uint8))
        min_area = _MIN_REGION_FRAC * h * w
        out = np.zeros((h, w), dtype=bool)
        for i in range(1, n):
            if stats[i, cv2.CC_STAT_AREA] >= min_area:
                out |= labels == i
        return out

    def _select_floor_mask(self, masks: np.ndarray, scores: np.ndarray,
                           h: int, w: int) -> np.ndarray:
        """Pick the floor mask from SAM's candidates, then clean it up.

        Selection mirrors the validated Colab behaviour (rank by SAM score) but
        prefers candidates that look like floor: they reach the bottom *band*
        (not just the literal last row -- SAM masks often stop a few px short)
        and are not oversized (walls/sky/buildings fill most of the frame).
        """
        bottom_start = h - max(1, int(h * _BOTTOM_TOUCH_FRAC))
        cands = []
        for m, s in zip(masks, scores):
            m = m.astype(bool)
            cov = float(m.mean())
            if cov == 0.0:
                continue
            cands.append({
                "mask": m, "score": float(s), "cov": cov,
                "touches": bool(m[bottom_start:].any()),
                "oversized": cov > _MAX_GROUND_FRAC,
            })

        if not cands:
            logger.warning("SAM returned no usable mask; returning empty ground mask")
            return np.zeros((h, w), dtype=bool)

        # Prefer floor-like candidates (reach the bottom band, not oversized).
        valid = [c for c in cands if c["touches"] and not c["oversized"]]
        if valid:
            chosen = max(valid, key=lambda c: c["score"])
        else:
            # Graceful fallback == Colab's argmax(score): never discard a
            # confident mask just because the heuristics were unsatisfied.
            chosen = max(cands, key=lambda c: c["score"])
            logger.warning(
                "No mask met bottom-touch/size heuristics; falling back to "
                "highest-score mask (score=%.3f, cov=%.1f%%)",
                chosen["score"], 100.0 * chosen["cov"],
            )

        mask = self._largest_component(chosen["mask"])

        # Constrain to the lower 60% -- but keep the original if the clip would
        # empty it (cleanup must never destroy a valid detection).
        clipped = mask.copy()
        clipped[: int(h * _LOWER_BAND_FRAC), :] = False
        if clipped.any():
            mask = clipped

        cleaned = self._remove_small(mask, h, w)
        return cleaned if cleaned.any() else mask


def filter_ground_depth(depth_map: np.ndarray, ground_mask: np.ndarray) -> np.ndarray:
    """
    Zero out ground pixels in ``depth_map`` (in place) and return it.

    Option B (set to 0) is chosen over NaN because
    ``navigation.run_detection_pipeline`` already (a) runs
    ``np.nan_to_num(depth, nan=0.0)`` and (b) filters depths with ``column > 0.0``
    in its free-zone analysis -- so 0 is exactly its existing "no valid surface"
    sentinel and floor pixels are ignored downstream for free.
    """
    if ground_mask.shape != depth_map.shape:
        # nearest-neighbour keeps the boolean mask crisp if resolutions differ
        ground_mask = cv2.resize(
            ground_mask.astype(np.uint8),
            (depth_map.shape[1], depth_map.shape[0]),
            interpolation=cv2.INTER_NEAREST,
        ).astype(bool)
    removed = int(ground_mask.sum())
    depth_map[ground_mask] = 0.0
    logger.info("Filtered %d ground pixels (%.1f%% of depth map)",
                removed, 100.0 * removed / depth_map.size)
    return depth_map


def save_debug(out_dir: str, frame: np.ndarray, ground_mask: np.ndarray,
               filtered_depth: np.ndarray) -> None:
    """Persist frame.jpg, ground_mask.png and filtered_depth.png for visual QA."""
    os.makedirs(out_dir, exist_ok=True)
    cv2.imwrite(os.path.join(out_dir, "frame.jpg"), frame)
    cv2.imwrite(os.path.join(out_dir, "ground_mask.png"),
                ground_mask.astype(np.uint8) * 255)

    valid = filtered_depth[np.isfinite(filtered_depth) & (filtered_depth > 0)]
    if valid.size:
        vmin, vmax = float(valid.min()), float(valid.max())
        norm = np.clip((filtered_depth - vmin) / max(vmax - vmin, 1e-6), 0.0, 1.0)
        vis = cv2.applyColorMap((norm * 255.0).astype(np.uint8), cv2.COLORMAP_INFERNO)
        vis[~np.isfinite(filtered_depth) | (filtered_depth <= 0)] = 0  # ground=black
    else:
        vis = np.zeros((*filtered_depth.shape, 3), dtype=np.uint8)
    cv2.imwrite(os.path.join(out_dir, "filtered_depth.png"), vis)
    logger.info("Saved SAM debug artefacts to %s/", out_dir)
