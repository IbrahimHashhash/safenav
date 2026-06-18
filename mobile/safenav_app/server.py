"""
api/server.py
=============
FastAPI server that runs the YOLOv11 + Depth-Anything-V2 pipeline live over a
WebSocket and emits navigation instructions for the SafeNav client.

Wire protocol
-------------
Client -> server (preferred, binary frame):
    [0:4]   uint32 BE frame_id
    [4]     uint8 flags  (bit 0 = include depth preview in the response)
    [5:]    raw JPEG bytes of the camera frame

Client -> server (legacy, text frame):
    JSON  {"frame_id": int, "include_depth": bool, "frame": <base64 JPEG>}

Server -> client (always):
    text JSON response (see :data:`RESPONSE_SCHEMA_DOC`).

Server -> client (when include_depth is true):
    up to three binary preview messages, each prefixed by
    [0:4]   uint32 BE frame_id
    [4]     uint8 flags  (bit 0 = depth, bit 1 = SAM ground segmentation,
                          bit 2 = YOLO detections, bit 3 = raw binary ground
                          mask as PNG -- exactly one bit per message)
    [5:]    JPEG bytes
    Sent immediately after the JSON; correlate to the JSON via frame_id and
    switch on the flags byte. Sending raw bytes avoids the ~33 % bandwidth and
    the CPU cost of base64.
"""
from __future__ import annotations

import asyncio
import base64
import io
import json
import logging
import os
import socket
import time
import traceback
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler

import cv2
import numpy as np
import torch
from PIL import Image
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

# project-local
from models.sam_ground_segmenter import filter_ground_depth, save_debug
from utils.navigation import init_tracker_state, run_detection_pipeline


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
DAV2_VARIANT     = os.environ.get("DAV2_VARIANT", "vitb")    # vits | vitb | vitl
DAV2_INPUT_SIZE  = int(os.environ.get("DAV2_INPUT_SIZE", 392))
DAV2_MAX_DEPTH_M = 15 # float(os.environ.get("DAV2_MAX_DEPTH_M", 80.0))

YOLO_VARIANT     = os.environ.get("YOLO_VARIANT", "yolo11s")
YOLO_INPUT_SIZE  = int(os.environ.get("YOLO_INPUT_SIZE", 512))
YOLO_CONF        = float(os.environ.get("YOLO_CONF", 0.50)) # confidence score

# campus feedback #1: only these COCO classes are treated as obstacles.
# Stairs come from the separate stairs detector; everything else is ignored.
DETECTED_OBSTACLES_IDS = frozenset({
    0,   # person
    2,   # car
    3,   # motorcycle
    5,   # bus
    13,  # bench
    56,  # chair
    60,  # dining table
})

# Second YOLO specialised on stairs. The base yolo11s has no 'stairs' class, so
# we keep ONLY this model's 'stairs' detections and merge them with the base
# model's COCO detections (disjoint -> no cross-model NMS needed). It runs every
# STAIRS_EVERY_N frames and the result is cached between runs to limit the extra
# GPU cost (stairs are static structures, unlike fast-moving traffic).
STAIRS_WEIGHTS    = os.environ.get("STAIRS_WEIGHTS", "stairs-detector")  # -> .pt
STAIRS_INPUT_SIZE = int(os.environ.get("STAIRS_INPUT_SIZE", YOLO_INPUT_SIZE))
STAIRS_CONF       = float(os.environ.get("STAIRS_CONF", 0.35))  # safety-critical: favour recall
STAIRS_CLASS      = os.environ.get("STAIRS_CLASS", "stairs")    # only this class is kept
STAIRS_EVERY_N    = int(os.environ.get("STAIRS_EVERY_N", 3))    # run every N frames, cache between

SAM_VARIANT      = os.environ.get("SAM_VARIANT", "small")   # tiny|small|base_plus|large
SAM_DEBUG        = os.environ.get("SAM_DEBUG", "0") == "1"   # dump debug artefacts
SAM_DEBUG_EVERY  = int(os.environ.get("SAM_DEBUG_EVERY", 60))  # ...every N frames

# campus feedback #5: skip near-identical frames to save GPU. We compare a tiny
# grayscale signature of each frame to the last PROCESSED one; if the mean
# absolute difference is below FRAME_SKIP_MAD the frame is considered unchanged
# and we reuse the previous result instead of re-running the models.
FRAME_SKIP_ENABLED    = os.environ.get("FRAME_SKIP", "1") == "1"
FRAME_SKIP_MAD        = float(os.environ.get("FRAME_SKIP_MAD", 3.0))  # 0-255 scale
FRAME_SKIP_MAX_CONSEC = int(os.environ.get("FRAME_SKIP_MAX_CONSEC", 30))  # force refresh
FRAME_SIG_DIM         = 32       # signature is FRAME_SIG_DIM x FRAME_SIG_DIM gray

DEPTH_PREVIEW_MAX_DIM = 320      # resize depth preview before JPEG encoding
DEPTH_PREVIEW_QUALITY = 70       # JPEG quality for depth preview
DEPTH_FLAG = 0x01                # bit 0 of flags byte = depth preview follows
SEG_FLAG   = 0x02                # bit 1 = SAM ground-segmentation preview follows
YOLO_FLAG  = 0x04                # bit 2 = YOLO detection preview follows
MASK_FLAG  = 0x08                # bit 3 = raw binary ground mask (PNG) follows
HEADER_SIZE = 5                  # 4B frame_id + 1B flags

ROLLING_WINDOW = 30              # frames kept in the timing window
LOG_EVERY_N_FRAMES = 30          # how often to flush a per-connection summary
SKIP_MODEL_LOAD = os.environ.get("SKIP_MODEL_LOAD", "0") == "1"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOG_DIR = os.path.join(PROJECT_ROOT, "logs")


# --------------------------------------------------------------------------- #
# Logging
# --------------------------------------------------------------------------- #
def _configure_logging() -> logging.Logger:
    """Set up file + console logging; safe to call multiple times."""
    os.makedirs(LOG_DIR, exist_ok=True)
    log_path = os.path.join(LOG_DIR, "server.log")

    fmt = logging.Formatter(
        "%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    root = logging.getLogger("safenav")
    root.setLevel(logging.INFO)

    # avoid stacking handlers on reload
    if not any(getattr(h, "_safenav_tag", False) for h in root.handlers):
        file_handler = RotatingFileHandler(
            log_path, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8"
        )
        file_handler.setFormatter(fmt)
        file_handler._safenav_tag = True  # type: ignore[attr-defined]
        root.addHandler(file_handler)

        console = logging.StreamHandler()
        console.setFormatter(fmt)
        console._safenav_tag = True  # type: ignore[attr-defined]
        root.addHandler(console)

    root.propagate = False
    return root


log = _configure_logging()


# --------------------------------------------------------------------------- #
# Inference workers
# --------------------------------------------------------------------------- #
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="infer")

# Lazily filled in lifespan startup. None means "model not available".
_yolo_detector = None    # type: ignore[var-annotated]
_dav2_model = None       # type: ignore[var-annotated]
_sam_segmenter = None    # type: ignore[var-annotated]
_stairs_detector = None  # type: ignore[var-annotated]


def _load_models() -> None:
    """Load YOLO + DAV2 once at startup; failures are logged, not fatal."""
    global _yolo_detector, _dav2_model, _sam_segmenter, _stairs_detector

    if SKIP_MODEL_LOAD:
        log.warning("SKIP_MODEL_LOAD=1 -- starting without inference models")
        return

    # YOLO
    try:
        from models.yolo_detector import YOLODetector
        _yolo_detector = YOLODetector(variant=YOLO_VARIANT, device=DEVICE)
        _yolo_detector.warm_up(input_size=YOLO_INPUT_SIZE)
        log.info("YOLO loaded (%s @ %dpx, device=%s)",
                 YOLO_VARIANT, YOLO_INPUT_SIZE, DEVICE)
    except Exception:
        log.exception("Failed to load YOLO model -- /ws/navigation will return errors")
        _yolo_detector = None

    # Stairs YOLO (optional second detector; only its 'stairs' class is used).
    try:
        from models.yolo_detector import YOLODetector
        _stairs_detector = YOLODetector(variant=STAIRS_WEIGHTS, device=DEVICE)
        _stairs_detector.warm_up(input_size=STAIRS_INPUT_SIZE)
        log.info("Stairs YOLO loaded (%s @ %dpx, class=%r, every %d frames)",
                 STAIRS_WEIGHTS, STAIRS_INPUT_SIZE, STAIRS_CLASS, STAIRS_EVERY_N)
    except Exception:
        log.exception("Failed to load stairs model -- stairs detection disabled")
        _stairs_detector = None

    # Depth-Anything-V2
    try:
        from models.depth_anything import DepthAnythingModel
        _dav2_model = DepthAnythingModel(
            variant=DAV2_VARIANT, device=DEVICE, max_depth=DAV2_MAX_DEPTH_M,
        )
        _dav2_model.warm_up()
        log.info("DAV2 loaded (%s @ %dpx, device=%s, fp16=%s)",
                 DAV2_VARIANT, DAV2_INPUT_SIZE, DEVICE, DEVICE == "cuda")
    except Exception:
        log.exception("Failed to load DAV2 model -- /ws/navigation will return errors")
        _dav2_model = None

    # SAM 2.1 ground segmenter (optional: if it fails, ground filtering is just
    # disabled and the pipeline still serves obstacle/navigation results).
    try:
        from models.sam_ground_segmenter import SAMGroundSegmenter
        _sam_segmenter = SAMGroundSegmenter(variant=SAM_VARIANT, device=DEVICE)
        log.info("SAM loaded (%s, device=%s)", SAM_VARIANT, DEVICE)
    except Exception:
        log.exception("Failed to load SAM model -- ground filtering disabled")
        _sam_segmenter = None


# --------------------------------------------------------------------------- #
# FastAPI app + lifespan
# --------------------------------------------------------------------------- #
@asynccontextmanager
async def _lifespan(app: FastAPI):
    log.info("Server starting up (device=%s)", DEVICE)
    _load_models()
    log.info("Server ready -- endpoints: /health, /ws/navigation")
    try:
        yield
    finally:
        log.info("Server shutting down")
        _executor.shutdown(wait=False, cancel_futures=True)


app = FastAPI(title="safenav-detection-pipeline", lifespan=_lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# --------------------------------------------------------------------------- #
# Frame decoding / encoding helpers
# --------------------------------------------------------------------------- #
def _decode_frame_message(message) -> dict:
    """
    Backward-compatible decoder.
    Preferred path: binary websocket frame  ([4B frame_id][1B flags][JPEG]).
    Legacy path:    JSON text with base64 payload.
    """
    # Starlette surfaces disconnects through receive() as a dict; surface it
    # as the proper exception type so the websocket loop can clean up.
    if message.get("type") == "websocket.disconnect":
        raise WebSocketDisconnect(code=message.get("code", 1000))

    raw_bytes = message.get("bytes")
    if raw_bytes is not None:
        if len(raw_bytes) < HEADER_SIZE:
            raise ValueError("Frame packet too small")
        return {
            "frame_id": int.from_bytes(raw_bytes[:4], "big"),
            "include_depth": bool(raw_bytes[4] & DEPTH_FLAG),
            "frame_bytes": raw_bytes[HEADER_SIZE:],
        }

    raw_text = message.get("text")
    if raw_text is None:
        raise ValueError("Unsupported websocket message type")

    payload = json.loads(raw_text)
    return {
        "frame_id": int(payload.get("frame_id", 0)),
        "include_depth": bool(payload.get("include_depth", False)),
        "frame_bytes": base64.b64decode(payload["frame"]),
    }


def _decode_bgr_frame(frame_bytes: bytes) -> np.ndarray:
    """JPEG bytes -> upright BGR np.ndarray.

    OpenCV >= 4.x's ``cv2.imdecode`` already auto-applies the JPEG's EXIF
    orientation, so phone frames (the camera layer tags them with EXIF) come out
    upright on their own. Frames re-encoded by OpenCV in the bundled test
    scripts carry NO EXIF tag; only for those do we keep the legacy 90° CW
    rotation (the scripts ``--pre-rotate`` to match). Applying that rotation to
    an already-EXIF-oriented phone frame is what turned the live feed 90°
    sideways -- the cause of the garbage detections and constant "narrow path".
    """
    arr = np.frombuffer(frame_bytes, np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)  # honours EXIF orientation
    if frame is None:
        raise ValueError("Invalid JPEG frame")

    # Presence of an EXIF Orientation tag distinguishes a real camera JPEG
    # (already oriented above) from an OpenCV-encoded one (no EXIF -> needs the
    # legacy rotation). Reading EXIF is metadata-only, so it's cheap.
    try:
        has_exif_orientation = (
            Image.open(io.BytesIO(frame_bytes)).getexif().get(0x0112) is not None
        )
    except Exception:
        has_exif_orientation = False

    if not has_exif_orientation:
        frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    return frame


def _frame_signature(bgr_frame: np.ndarray) -> np.ndarray:
    """Tiny grayscale fingerprint used to detect near-identical frames cheaply."""
    small = cv2.resize(bgr_frame, (FRAME_SIG_DIM, FRAME_SIG_DIM),
                       interpolation=cv2.INTER_AREA)
    return cv2.cvtColor(small, cv2.COLOR_BGR2GRAY).astype(np.float32)


def _colorize_depth(depth: np.ndarray) -> np.ndarray:
    """Map a metric depth map to an 8-bit colourised BGR image."""
    valid = depth[np.isfinite(depth) & (depth > 0)]
    if valid.size == 0:
        return np.zeros((*depth.shape, 3), dtype=np.uint8)
    vmin = float(valid.min())
    vmax = float(valid.max())
    span = max(vmax - vmin, 1e-6)
    norm = np.clip((depth - vmin) / span, 0.0, 1.0)
    return cv2.applyColorMap((norm * 255.0).astype(np.uint8), cv2.COLORMAP_INFERNO)


def _encode_preview_bgr(img: np.ndarray) -> bytes | None:
    """Downscale a BGR image and JPEG-encode it. Returns raw JPEG bytes."""
    # downscale to keep bandwidth and encode time low
    h, w = img.shape[:2]
    scale = DEPTH_PREVIEW_MAX_DIM / float(max(h, w))
    if scale < 1.0:
        img = cv2.resize(
            img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA,
        )
    ok, buf = cv2.imencode(
        ".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, DEPTH_PREVIEW_QUALITY],
    )
    return buf.tobytes() if ok else None


def _encode_depth_preview(depth: np.ndarray) -> bytes | None:
    """Colourise + JPEG-encode a depth map. Returns raw JPEG bytes (no base64)."""
    return _encode_preview_bgr(_colorize_depth(depth))


def _encode_seg_preview(frame: np.ndarray, ground_mask: np.ndarray | None) -> bytes | None:
    """Tint SAM's ground pixels red over the frame so the mask is verifiable."""
    if ground_mask is None:
        return None
    overlay = frame.copy()
    overlay[ground_mask] = (0, 0, 255)  # BGR red where SAM marked ground
    blended = cv2.addWeighted(frame, 0.6, overlay, 0.4, 0.0)
    return _encode_preview_bgr(blended)


def _hex_to_bgr(hex_color: str) -> tuple[int, int, int]:
    h = hex_color.lstrip("#")
    return (int(h[4:6], 16), int(h[2:4], 16), int(h[0:2], 16))  # B, G, R


def _encode_yolo_preview(frame: np.ndarray, detections: list[dict]) -> bytes | None:
    """Draw every YOLO detection (box + label + confidence) over the frame."""
    vis = frame.copy()
    for d in detections:
        x1, y1, x2, y2 = (int(v) for v in d["bbox"])
        color = _hex_to_bgr(d.get("color", "#00FF00"))
        cv2.rectangle(vis, (x1, y1), (x2, y2), color, 2)
        text = f"{d.get('label', '')} {d.get('confidence', 0.0):.2f}"
        cv2.putText(vis, text, (x1, max(12, y1 - 5)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 1, cv2.LINE_AA)
    return _encode_preview_bgr(vis)


def _encode_mask_preview(ground_mask: np.ndarray | None) -> bytes | None:
    """Encode the raw boolean ground mask as a full-res 1-channel PNG.

    Unlike the visual previews this is NOT downscaled: clients (e.g. the video
    annotator) need the exact mask to overlay at full resolution. A binary mask
    compresses to only a few KB as PNG, so full-res is cheap.
    """
    if ground_mask is None:
        return None
    ok, buf = cv2.imencode(".png", ground_mask.astype(np.uint8) * 255)
    return buf.tobytes() if ok else None


# --------------------------------------------------------------------------- #
# Inference wrappers (each returns elapsed_ms so we can log timings)
# --------------------------------------------------------------------------- #
_CLASS_COLORS = (
    "#FF5733", "#33A1FF", "#FF33A8", "#33FF57", "#FFD433",
    "#A833FF", "#FF8C33", "#33FFF5", "#FF3380", "#80FF33",
    "#FF33D4", "#33FFAA", "#FFB533", "#3380FF", "#FF3355",
    "#33FFD4", "#FFE033", "#5533FF", "#FF6633", "#33FF80",
)


def _class_color(class_id: int) -> str:
    return _CLASS_COLORS[class_id % len(_CLASS_COLORS)]


def _run_depth(bgr_frame: np.ndarray) -> tuple[np.ndarray, float]:
    if _dav2_model is None:
        raise RuntimeError("DAV2 model is not loaded")
    t0 = time.perf_counter()
    depth = _dav2_model.infer(bgr_frame, input_size=DAV2_INPUT_SIZE)
    return depth, (time.perf_counter() - t0) * 1000.0


def _run_sam(bgr_frame: np.ndarray) -> tuple[np.ndarray, float]:
    if _sam_segmenter is None:
        raise RuntimeError("SAM model is not loaded")
    t0 = time.perf_counter()
    # read-only: get_ground_mask does its own RGB copy, so sharing is safe.
    mask = _sam_segmenter.get_ground_mask(bgr_frame)
    return mask, (time.perf_counter() - t0) * 1000.0


def _run_yolo(bgr_frame: np.ndarray) -> tuple[list[dict], float]:
    if _yolo_detector is None:
        raise RuntimeError("YOLO model is not loaded")
    t0 = time.perf_counter()
    results = _yolo_detector.detect(
        bgr_frame, imgsz=YOLO_INPUT_SIZE, conf=YOLO_CONF,
    )
    elapsed_ms = (time.perf_counter() - t0) * 1000.0

    detections: list[dict] = []
    names = _yolo_detector.model.names
    for box in results[0].boxes:
        class_id = int(box.cls[0])
        if class_id not in DETECTED_OBSTACLES_IDS:
            continue  # campus feedback #1: ignore non-obstacle classes
        x1, y1, x2, y2 = box.xyxy[0].tolist()
        detections.append({
            "label":      names[class_id],
            "class_id":   class_id,
            "confidence": round(float(box.conf[0]), 3),
            "color":      _class_color(class_id),
            # navigation.py expects pixel coords on the rotated frame
            "bbox": [x1, y1, x2, y2],
        })
    return detections, elapsed_ms


def _run_stairs(bgr_frame: np.ndarray) -> tuple[list[dict], float]:
    """Run the stairs detector and keep ONLY its STAIRS_CLASS detections.

    The other classes this model emits (car/bench/human) are weaker duplicates
    of the base YOLO's COCO output, so we drop them -- leaving a detection set
    that is disjoint from the base model's and needs no cross-model NMS.
    """
    if _stairs_detector is None:
        raise RuntimeError("Stairs model is not loaded")
    t0 = time.perf_counter()
    results = _stairs_detector.detect(
        bgr_frame, imgsz=STAIRS_INPUT_SIZE, conf=STAIRS_CONF,
    )
    elapsed_ms = (time.perf_counter() - t0) * 1000.0

    detections: list[dict] = []
    names = _stairs_detector.model.names
    for box in results[0].boxes:
        class_id = int(box.cls[0])
        if names[class_id] != STAIRS_CLASS:
            continue
        x1, y1, x2, y2 = box.xyxy[0].tolist()
        detections.append({
            "label":      names[class_id],
            "class_id":   class_id,
            "confidence": round(float(box.conf[0]), 3),
            "color":      "#B026FF",  # distinct purple so stairs stand out
            "bbox": [x1, y1, x2, y2],
        })
    return detections, elapsed_ms


# --------------------------------------------------------------------------- #
# REST endpoints
# --------------------------------------------------------------------------- #
@app.get("/health")
async def health() -> dict:
    return {
        "status": "ok",
        "device": DEVICE,
        "models": {
            "yolo": {
                "loaded": _yolo_detector is not None,
                "variant": YOLO_VARIANT,
                "input_size": YOLO_INPUT_SIZE,
                "conf_threshold": YOLO_CONF,
            },
            "dav2": {
                "loaded": _dav2_model is not None,
                "variant": DAV2_VARIANT,
                "input_size": DAV2_INPUT_SIZE,
                "max_depth_m": DAV2_MAX_DEPTH_M,
                "fp16": DEVICE == "cuda",
            },
            "sam": {
                "loaded": _sam_segmenter is not None,
                "variant": SAM_VARIANT,
                "role": "ground_segmentation",
            },
            "stairs": {
                "loaded": _stairs_detector is not None,
                "weights": STAIRS_WEIGHTS,
                "class": STAIRS_CLASS,
                "conf_threshold": STAIRS_CONF,
                "every_n_frames": STAIRS_EVERY_N,
            },
        },
        "endpoints": ["/health", "/ws/navigation"],
    }


# --------------------------------------------------------------------------- #
# WebSocket endpoint
# --------------------------------------------------------------------------- #
def _rolling_avg(samples: deque, key: str) -> float:
    if not samples:
        return 0.0
    return float(sum(s[key] for s in samples) / len(samples))


@app.websocket("/ws/navigation")
async def navigation_ws(websocket: WebSocket) -> None:
    await websocket.accept()
    addr = f"{websocket.client.host}:{websocket.client.port}"
    log.info("Client connected: %s [/ws/navigation]", addr)

    if _yolo_detector is None or _dav2_model is None:
        log.warning("Refusing connection from %s: models not loaded", addr)
        await websocket.send_text(json.dumps({
            "error": "Models not loaded on the server (see /health)",
        }))
        await websocket.close(code=1011)
        return

    if _sam_segmenter is None:
        log.warning("SAM not loaded for %s: ground pixels will NOT be filtered", addr)

    tracker_state = init_tracker_state()
    loop = asyncio.get_running_loop()

    timings: deque[dict] = deque(maxlen=ROLLING_WINDOW)
    frames_processed = 0
    frames_failed = 0
    frames_skipped = 0
    connection_t0 = time.perf_counter()

    # Stairs run every STAIRS_EVERY_N frames; the last result is cached and
    # merged into detections on the in-between frames (stairs barely move).
    stairs_tick = 0
    stairs_cache: list[dict] = []

    # Frame-similarity skip (#5): fingerprint of the last PROCESSED frame, the
    # last full JSON response (reused on skipped frames), and a consecutive-skip
    # counter that forces a refresh after FRAME_SKIP_MAX_CONSEC skips.
    last_sig: np.ndarray | None = None
    last_response: dict | None = None
    consec_skips = 0

    try:
        while True:
            t_total = time.perf_counter()

            # ---- 1) receive + decode --------------------------------------
            try:
                message = await websocket.receive()
                payload = _decode_frame_message(message)
            except WebSocketDisconnect:
                raise
            except Exception as exc:
                frames_failed += 1
                log.warning("Bad frame from %s: %s", addr, exc)
                await websocket.send_text(json.dumps({"error": f"Bad frame: {exc}"}))
                continue

            t_decode = time.perf_counter()
            try:
                frame = _decode_bgr_frame(payload["frame_bytes"])
            except Exception as exc:
                frames_failed += 1
                log.warning("Decode failure from %s: %s", addr, exc)
                await websocket.send_text(json.dumps({
                    "frame_id": payload.get("frame_id", 0),
                    "error": f"Decode failure: {exc}",
                }))
                continue
            decode_ms = (time.perf_counter() - t_decode) * 1000.0

            frame_id = payload["frame_id"]
            include_depth = payload["include_depth"]
            frame_h, frame_w = frame.shape[:2]

            # ---- 1b) frame-similarity skip (#5) --------------------------
            # If this frame is near-identical to the last one we actually
            # processed, reuse that result instead of re-running the models.
            sig = _frame_signature(frame)
            if (FRAME_SKIP_ENABLED and last_response is not None and last_sig is not None
                    and consec_skips < FRAME_SKIP_MAX_CONSEC
                    and float(np.mean(np.abs(sig - last_sig))) < FRAME_SKIP_MAD):
                consec_skips += 1
                frames_skipped += 1
                skip_resp = dict(last_response)
                skip_resp.update({
                    "frame_id": frame_id, "skipped": True,
                    "depth_attached": False, "seg_attached": False,
                    "yolo_attached": False, "mask_attached": False,
                })
                await websocket.send_text(json.dumps(skip_resp))
                continue
            consec_skips = 0
            last_sig = sig

            # ---- 2) run YOLO + DAV2 (+ SAM) in parallel ------------------
            try:
                # one .copy() per model guards against ultralytics' in-place
                # ops; DAV2 and SAM only read the buffer so they can share it.
                depth_future = loop.run_in_executor(_executor, _run_depth, frame)
                yolo_future = loop.run_in_executor(_executor, _run_yolo, frame.copy())
                sam_future = (loop.run_in_executor(_executor, _run_sam, frame)
                              if _sam_segmenter is not None else None)
                # only fire the stairs detector every Nth frame (cache otherwise)
                run_stairs = (_stairs_detector is not None
                              and stairs_tick % STAIRS_EVERY_N == 0)
                stairs_future = (loop.run_in_executor(_executor, _run_stairs, frame.copy())
                                 if run_stairs else None)

                depth_map, depth_ms = await depth_future
                detections, yolo_ms = await yolo_future
                if sam_future is not None:
                    ground_mask, sam_ms = await sam_future
                else:
                    ground_mask, sam_ms = None, 0.0
                if stairs_future is not None:
                    stairs_cache, stairs_ms = await stairs_future  # refresh cache
                else:
                    stairs_ms = 0.0                                # reuse cache
            except Exception:
                frames_failed += 1
                log.exception("Inference failure from %s frame %d", addr, frame_id)
                await websocket.send_text(json.dumps({
                    "frame_id": frame_id, "error": "Inference failure",
                }))
                continue
            stairs_tick += 1

            # merge base-YOLO obstacles with the (possibly cached) stairs
            # detections -- the two class sets are disjoint, so no NMS needed.
            detections = detections + stairs_cache

            # ---- 3) remove ground pixels from the depth map --------------
            # Floor pixels are zeroed so navigation never treats the close
            # floor as an obstacle (free-zone analysis ignores depth == 0).
            if ground_mask is not None:
                filter_ground_depth(depth_map, ground_mask)
                if SAM_DEBUG and frames_processed % SAM_DEBUG_EVERY == 0:
                    save_debug(os.path.join(PROJECT_ROOT, "debug"),
                               frame, ground_mask, depth_map)

            # ---- 4) navigation pipeline ----------------------------------
            t_nav = time.perf_counter()
            try:
                result = run_detection_pipeline(
                    yolo_detections=detections,
                    depth_map=depth_map,
                    frame_w=frame_w,
                    frame_h=frame_h,
                    tracker_state=tracker_state,
                )
            except Exception:
                frames_failed += 1
                log.exception("Navigation failure from %s frame %d", addr, frame_id)
                await websocket.send_text(json.dumps({
                    "frame_id": frame_id, "error": "Navigation failure",
                }))
                continue
            nav_ms = (time.perf_counter() - t_nav) * 1000.0

            # ---- 4) normalise obstacle bboxes for the client -------------
            for ob in result["obstacles"]:
                x1, y1, x2, y2 = ob["bbox"]
                ob["bbox_px"] = [int(x1), int(y1), int(x2), int(y2)]
                ob["bbox"] = [
                    round(x1 / frame_w, 4), round(y1 / frame_h, 4),
                    round(x2 / frame_w, 4), round(y2 / frame_h, 4),
                ]
            # NOTE: highest_priority is the SAME dict object as one of the
            # obstacles above (navigation sets it to obstacles[0]), so it has
            # already been normalised in place -- re-normalising it here would
            # double-divide and collapse bbox_px to ~[0,0,1,0].

            # ---- 5) encode previews (if requested) -----------------------
            t_encode = time.perf_counter()
            if include_depth:
                depth_jpeg = _encode_depth_preview(depth_map)
                seg_jpeg = _encode_seg_preview(frame, ground_mask)
                yolo_jpeg = _encode_yolo_preview(frame, detections)
                mask_png = _encode_mask_preview(ground_mask)
            else:
                depth_jpeg = seg_jpeg = yolo_jpeg = mask_png = None
            encode_ms = (time.perf_counter() - t_encode) * 1000.0

            total_ms = (time.perf_counter() - t_total) * 1000.0

            # ---- 6) accumulate stats -------------------------------------
            timings.append({
                "decode_ms": decode_ms,
                "yolo_ms": yolo_ms,
                "depth_ms": depth_ms,
                "sam_ms": sam_ms,
                "stairs_ms": stairs_ms,
                "nav_ms": nav_ms,
                "encode_ms": encode_ms,
                "total_ms": total_ms,
            })
            frames_processed += 1

            # ---- 7) build the rich JSON response -------------------------
            response = {
                "frame_id": frame_id,
                "instruction": result["instruction"],
                "highest_priority": result["highest_priority"],
                "obstacles": result["obstacles"],
                "free_zones": result["free_zones"],
                "frame_size": {"w": frame_w, "h": frame_h},
                "metrics": {
                    "decode_ms": round(decode_ms, 2),
                    "yolo_ms": round(yolo_ms, 2),
                    "depth_ms": round(depth_ms, 2),
                    "sam_ms": round(sam_ms, 2),
                    "stairs_ms": round(stairs_ms, 2),
                    "nav_ms": round(nav_ms, 2),
                    "encode_ms": round(encode_ms, 2),
                    "total_ms": round(total_ms, 2),
                    "server_fps": round(1000.0 / total_ms, 2) if total_ms > 0 else 0.0,
                    "rolling_fps": (
                        round(1000.0 / _rolling_avg(timings, "total_ms"), 2)
                        if timings else 0.0
                    ),
                    "rolling": {
                        "decode_ms": round(_rolling_avg(timings, "decode_ms"), 2),
                        "yolo_ms":   round(_rolling_avg(timings, "yolo_ms"), 2),
                        "depth_ms":  round(_rolling_avg(timings, "depth_ms"), 2),
                        "sam_ms":    round(_rolling_avg(timings, "sam_ms"), 2),
                        "stairs_ms": round(_rolling_avg(timings, "stairs_ms"), 2),
                        "nav_ms":    round(_rolling_avg(timings, "nav_ms"), 2),
                        "encode_ms": round(_rolling_avg(timings, "encode_ms"), 2),
                        "total_ms":  round(_rolling_avg(timings, "total_ms"), 2),
                    },
                    "frames_processed": frames_processed,
                    "frames_failed":    frames_failed,
                    "frames_skipped":   frames_skipped,
                    "connection_uptime_s": round(time.perf_counter() - connection_t0, 1),
                },
                "device": DEVICE,
                "input_size": {"yolo": YOLO_INPUT_SIZE, "dav2": DAV2_INPUT_SIZE},
                "skipped": False,
                "depth_attached": depth_jpeg is not None,
                "seg_attached": seg_jpeg is not None,
                "yolo_attached": yolo_jpeg is not None,
                "mask_attached": mask_png is not None,
            }
            # cache for the frame-similarity skip path (#5)
            last_response = response

            await websocket.send_text(json.dumps(response))

            # each preview ships as a separate binary message; the flags byte
            # in the header tells the client which preview it is.
            for jpeg, flag in (
                (depth_jpeg, DEPTH_FLAG),
                (seg_jpeg, SEG_FLAG),
                (yolo_jpeg, YOLO_FLAG),
                (mask_png, MASK_FLAG),
            ):
                if jpeg is not None:
                    header = frame_id.to_bytes(4, "big") + bytes([flag])
                    await websocket.send_bytes(header + jpeg)

            # ---- 8) periodic file log ------------------------------------
            if frames_processed % LOG_EVERY_N_FRAMES == 0:
                log.info(
                    "[%s] frames=%d failed=%d skipped=%d fps=%.1f "
                    "decode=%.1fms yolo=%.1fms depth=%.1fms sam=%.1fms stairs=%.1fms nav=%.1fms total=%.1fms",
                    addr, frames_processed, frames_failed, frames_skipped,
                    1000.0 / _rolling_avg(timings, "total_ms"),
                    _rolling_avg(timings, "decode_ms"),
                    _rolling_avg(timings, "yolo_ms"),
                    _rolling_avg(timings, "depth_ms"),
                    _rolling_avg(timings, "sam_ms"),
                    _rolling_avg(timings, "stairs_ms"),
                    _rolling_avg(timings, "nav_ms"),
                    _rolling_avg(timings, "total_ms"),
                )

    except WebSocketDisconnect:
        log.info("Client disconnected: %s (frames=%d failed=%d uptime=%.1fs)",
                 addr, frames_processed, frames_failed,
                 time.perf_counter() - connection_t0)
    except Exception:
        log.error("Unhandled error from %s\n%s", addr, traceback.format_exc())
        try:
            await websocket.send_text(json.dumps({"error": "Server error"}))
        except Exception:
            pass


# --------------------------------------------------------------------------- #
# Utility used by main.py (kept here so server.py owns its own surface)
# --------------------------------------------------------------------------- #
def get_lan_ip() -> str:
    """Best-effort LAN IP discovery (works without internet)."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
    except Exception:
        try:
            ip = socket.gethostbyname(socket.gethostname())
        except Exception:
            ip = "127.0.0.1"
    finally:
        s.close()
    return ip
