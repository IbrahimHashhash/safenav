"""
api/server.py — FastAPI server for SafeNav obstacle avoidance.

Runs YOLO + Depth-Anything-V2 on each camera frame received over WebSocket
and returns a navigation instruction + obstacle data to the client.

Wire protocol (client -> server):
    Binary: [4B frame_id][1B flags][JPEG bytes]

Wire protocol (server -> client):
    JSON response with instruction, obstacles, free_zones, metrics.
    Optional binary preview messages (depth/YOLO/freezone) with same header format.
"""
from __future__ import annotations

import asyncio
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
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

# project-local
from utils.navigation import (
    run_detection_pipeline,
    obstacle_patch_depth,
    _BAND_TOP_FRAC as NAV_BAND_TOP_FRAC,
    _BAND_BOTTOM_FRAC as NAV_BAND_BOTTOM_FRAC,
    _ZONE_NAMES as NAV_ZONE_NAMES,
)


# --------------------------------------------------------------------------- #
# Configuration
# --------------------------------------------------------------------------- #
DAV2_VARIANT     = os.environ.get("DAV2_VARIANT", "vitb")
DAV2_INPUT_SIZE  = int(os.environ.get("DAV2_INPUT_SIZE", 392))
DAV2_MAX_DEPTH_M = 16

YOLO_VARIANT     = os.environ.get("YOLO_VARIANT", "yolo11s")
YOLO_INPUT_SIZE  = int(os.environ.get("YOLO_INPUT_SIZE", 512))
YOLO_CONF        = float(os.environ.get("YOLO_CONF", 0.50))

# only these COCO classes are treated as obstacles
DETECTED_OBSTACLES_IDS = frozenset({
    0,   # person
    2,   # car
    # 3,   # motorcycle
    # 5,   # bus
    13,  # bench
    # 56,  # chair
    # 60,  # dining table
})

# separate stairs detector (base YOLO has no stairs class)
STAIRS_WEIGHTS    = os.environ.get("STAIRS_WEIGHTS", "stairs-detector")
STAIRS_INPUT_SIZE = int(os.environ.get("STAIRS_INPUT_SIZE", YOLO_INPUT_SIZE))
STAIRS_CONF       = float(os.environ.get("STAIRS_CONF", 0.3))
STAIRS_CLASS      = os.environ.get("STAIRS_CLASS", "stairs")

# skip near-identical frames to save GPU
FRAME_SKIP_ENABLED    = os.environ.get("FRAME_SKIP", "1") == "1"
FRAME_SKIP_MAD        = float(os.environ.get("FRAME_SKIP_MAD", 20.0))
FRAME_SKIP_MAX_CONSEC = int(os.environ.get("FRAME_SKIP_MAX_CONSEC", 30))
FRAME_SIG_DIM         = 32

DEPTH_PREVIEW_MAX_DIM = 320
DEPTH_PREVIEW_QUALITY = 70
HQ_PREVIEW_QUALITY = 95

# binary message flags (client -> server request bits)
REQ_PREVIEWS_FLAG = 0x01
REQ_HQ_FLAG       = 0x02

# binary message flags (server -> client preview type)
DEPTH_FLAG = 0x01
YOLO_FLAG  = 0x04
FREEZONE_FLAG = 0x10
HEADER_SIZE = 5  # 4B frame_id + 1B flags

ROLLING_WINDOW = 30
LOG_EVERY_N_FRAMES = 30
SKIP_MODEL_LOAD = os.environ.get("SKIP_MODEL_LOAD", "0") == "1"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOG_DIR = os.path.join(PROJECT_ROOT, "logs")


# Logging
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


# Inference workers
_executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="infer")

# Lazily filled in lifespan startup. None means "model not available".
_yolo_detector = None    
_dav2_model = None      
_stairs_detector = None 


def _load_models() -> None:
    """Load YOLO + DAV2 once at startup; failures are logged, not fatal."""
    global _yolo_detector, _dav2_model, _stairs_detector

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
        log.exception("Failed to load YOLO model -- /ws/avoidance will return errors")
        _yolo_detector = None

    # Stairs YOLO
    try:
        from models.yolo_detector import YOLODetector
        _stairs_detector = YOLODetector(variant=STAIRS_WEIGHTS, device=DEVICE)
        _stairs_detector.warm_up(input_size=STAIRS_INPUT_SIZE)
        log.info("Stairs YOLO loaded (%s @ %dpx, class=%r)",
                 STAIRS_WEIGHTS, STAIRS_INPUT_SIZE, STAIRS_CLASS)
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
        log.exception("Failed to load DAV2 model -- /ws/avoidance will return errors")
        _dav2_model = None


# FastAPI app + lifespan
@asynccontextmanager
async def _lifespan(app: FastAPI):
    log.info("Server starting up (device=%s)", DEVICE)
    _load_models()
    log.info("Server ready -- endpoints: /health, /ws/avoidance")
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


# Frame decoding / encoding helpers
def _decode_frame_message(message) -> dict:
    """Parse a binary WebSocket message into frame_id, flags, and JPEG bytes."""
    # Starlette sometimes delivers disconnects as a dict instead of an exception
    if message.get("type") == "websocket.disconnect":
        raise WebSocketDisconnect(code=message.get("code", 1000))

    raw_bytes = message.get("bytes")
    if raw_bytes is None or len(raw_bytes) < HEADER_SIZE:
        raise ValueError("Expected binary frame with at least 5 bytes")
    return {
        "frame_id": int.from_bytes(raw_bytes[:4], "big"),
        "include_depth": bool(raw_bytes[4] & DEPTH_FLAG),
        "hq": bool(raw_bytes[4] & REQ_HQ_FLAG),
        "frame_bytes": raw_bytes[HEADER_SIZE:],
    }


def _decode_bgr_frame(frame_bytes: bytes) -> np.ndarray:
    """JPEG bytes -> BGR numpy array."""
    arr = np.frombuffer(frame_bytes, np.uint8)
    frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if frame is None:
        raise ValueError("Invalid JPEG frame")
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


def _encode_preview_bgr(img: np.ndarray, hq: bool = False) -> bytes | None:
    """JPEG-encode a BGR image. Downscales unless hq=True."""
    if not hq:
        # downscale to keep bandwidth and encode time low
        h, w = img.shape[:2]
        scale = DEPTH_PREVIEW_MAX_DIM / float(max(h, w))
        if scale < 1.0:
            img = cv2.resize(
                img, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA,
            )
    quality = HQ_PREVIEW_QUALITY if hq else DEPTH_PREVIEW_QUALITY
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    return buf.tobytes() if ok else None


def _encode_depth_preview(depth: np.ndarray, hq: bool = False) -> bytes | None:
    """Colourise + JPEG-encode a depth map. Returns raw JPEG bytes (no base64)."""
    return _encode_preview_bgr(_colorize_depth(depth), hq)


# urgency -> BGR box colour (dark so white text stays legible)
_URGENCY_COLOR = {
    "CRITICAL": (0, 0, 150),     # dark red
    "HIGH":     (0, 70, 150),    # dark orange
    "MEDIUM":   (0, 100, 130),   # dark amber
    "LOW":      (0, 110, 0),     # dark green
}


def _encode_yolo_preview(frame: np.ndarray, obstacles: list[dict],
                         hq: bool = False) -> bytes | None:
    """Draw bounding boxes with label/distance/confidence on the frame."""
    vis = frame.copy()
    h = vis.shape[0]
    font = cv2.FONT_HERSHEY_SIMPLEX
    fs = max(0.45, h / 1100.0)          # adaptive font scale
    th = max(1, round(h / 500.0))       # adaptive line/box thickness
    for ob in obstacles:
        bx = ob.get("bbox_px") or ob.get("bbox")
        if not bx:
            continue
        x1, y1, x2, y2 = (int(v) for v in bx[:4])
        color = _URGENCY_COLOR.get(ob.get("urgency"), (0, 255, 0))
        cv2.rectangle(vis, (x1, y1), (x2, y2), color, th)

        dist = ob.get("distance_m")
        dist_txt = f"{float(dist):.1f}m" if dist is not None else "?m"
        text = f"{ob.get('label', '?')} {dist_txt} {float(ob.get('confidence', 0.0)):.2f}"

        (tw, tht), base = cv2.getTextSize(text, font, fs, th)
        y_text = y1 - 6 if (y1 - tht - base - 4) > 0 else y2 + tht + base + 4
        # filled background for readability
        cv2.rectangle(vis, (x1, y_text - tht - base),
                      (x1 + tw, y_text + base), color, -1)
        cv2.putText(vis, text, (x1, y_text), font, fs,
                    (255, 255, 255), max(1, th - 1), cv2.LINE_AA)
    return _encode_preview_bgr(vis, hq)


def _encode_freezones_preview(frame: np.ndarray, free_zones: dict | None,
                              hq: bool = False) -> bytes | None:
    """Draw the 5 free-zone lanes over the frame (green = clear, red = blocked)."""
    if not free_zones:
        return None
    vis = frame.copy()
    h, w = vis.shape[:2]
    band_top = int(h * NAV_BAND_TOP_FRAC)
    band_bot = int(h * NAV_BAND_BOTTOM_FRAC)
    edges = np.linspace(0, w, len(NAV_ZONE_NAMES) + 1, dtype=int)

    # translucent green/red fill per lane (only inside the analysed band)
    overlay = vis.copy()
    for i, name in enumerate(NAV_ZONE_NAMES):
        z = free_zones.get(name, {})
        color = (0, 180, 0) if z.get("clear") else (0, 0, 255)  # BGR
        cv2.rectangle(overlay, (edges[i], band_top), (edges[i + 1], band_bot), color, -1)
    vis = cv2.addWeighted(overlay, 0.35, vis, 0.65, 0.0)

    # lane borders + clearance labels
    for i, name in enumerate(NAV_ZONE_NAMES):
        cv2.rectangle(vis, (edges[i], band_top), (edges[i + 1], band_bot),
                      (255, 255, 255), 1)
        z = free_zones.get(name, {})
        txt = f"{z.get('clearance_m', '?')}m"
        cv2.putText(vis, txt, (edges[i] + 3, band_bot - 6),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, (255, 255, 255), 1, cv2.LINE_AA)
    return _encode_preview_bgr(vis, hq)


# Inference wrappers (each returns result + elapsed_ms)
def _run_depth(bgr_frame: np.ndarray) -> tuple[np.ndarray, float]:
    if _dav2_model is None:
        raise RuntimeError("DAV2 model is not loaded")
    t0 = time.perf_counter()
    depth = _dav2_model.infer(bgr_frame, input_size=DAV2_INPUT_SIZE)
    return depth, (time.perf_counter() - t0) * 1000.0


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
            continue
        x1, y1, x2, y2 = box.xyxy[0].tolist()
        detections.append({
            "label":      names[class_id],
            "class_id":   class_id,
            "confidence": round(float(box.conf[0]), 3),
            "bbox": [x1, y1, x2, y2],
        })
    return detections, elapsed_ms


def _run_stairs(bgr_frame: np.ndarray) -> tuple[list[dict], float]:
    """Run the stairs detector; only keep its 'stairs' class detections."""
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


# REST endpoints
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
            "stairs": {
                "loaded": _stairs_detector is not None,
                "weights": STAIRS_WEIGHTS,
                "class": STAIRS_CLASS,
                "conf_threshold": STAIRS_CONF,
            },
        },
        "endpoints": ["/health", "/ws/avoidance", "/ws/raw_depth"],
    }


# WebSocket endpoint
def _rolling_avg(samples: deque, key: str) -> float:
    if not samples:
        return 0.0
    return float(sum(s[key] for s in samples) / len(samples))


@app.websocket("/ws/avoidance")
async def navigation_ws(websocket: WebSocket) -> None:
    await websocket.accept()
    addr = f"{websocket.client.host}:{websocket.client.port}"
    log.info("Client connected: %s [/ws/avoidance]", addr)

    if _yolo_detector is None or _dav2_model is None:
        log.warning("Refusing connection from %s: models not loaded", addr)
        await websocket.send_text(json.dumps({
            "error": "Models not loaded on the server (see /health)",
        }))
        await websocket.close(code=1011)
        return

    loop = asyncio.get_running_loop()

    timings: deque[dict] = deque(maxlen=ROLLING_WINDOW)
    frames_processed = 0
    frames_failed = 0
    frames_skipped = 0
    connection_t0 = time.perf_counter()

    # frame-skip state: reuse last result if the frame barely changed
    last_sig: np.ndarray | None = None
    last_response: dict | None = None
    consec_skips = 0

    try:
        while True:
            # 1) receive + decode 
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

            t_total = time.perf_counter()

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

            # 1b) frame-skip: reuse last result if frame barely changed
            sig = _frame_signature(frame)
            sig_mad = -1
            if last_sig is not None:
                sig_mad = float(np.mean(np.abs(sig - last_sig)))
    
            if (FRAME_SKIP_ENABLED 
                    and last_response is not None 
                    and last_sig is not None
                    and consec_skips < FRAME_SKIP_MAX_CONSEC
                    and sig_mad < FRAME_SKIP_MAD):
                consec_skips += 1
                frames_skipped += 1
                skip_resp = dict(last_response)
                skip_resp.update({
                    "frame_id": frame_id, "skipped": True,
                    "sig_mad": round(sig_mad, 4),
                    "depth_attached": False,
                    "yolo_attached": False,
                })
                await websocket.send_text(json.dumps(skip_resp))
                continue
            consec_skips = 0
            last_sig = sig

            # 2) run YOLO + depth + stairs in parallel
            try:
                depth_future = loop.run_in_executor(_executor, _run_depth, frame)
                yolo_future = loop.run_in_executor(_executor, _run_yolo, frame.copy())
                stairs_future = (loop.run_in_executor(_executor, _run_stairs, frame.copy())
                                 if _stairs_detector is not None else None)

                depth_map, depth_ms = await depth_future
                detections, yolo_ms = await yolo_future
                stairs_dets, stairs_ms = (
                    await stairs_future if stairs_future is not None else ([], 0.0)
                )
            except Exception:
                frames_failed += 1
                log.exception("Inference failure from %s frame %d", addr, frame_id)
                await websocket.send_text(json.dumps({
                    "frame_id": frame_id, "error": "Inference failure",
                }))
                continue

            # merge base YOLO + stairs detections (disjoint classes, no NMS needed)
            detections = detections + stairs_dets

            # 3) navigation pipeline 
            t_nav = time.perf_counter()
            try:
                result = run_detection_pipeline(
                    yolo_detections=detections,
                    depth_map=depth_map,
                    frame_w=frame_w,
                    frame_h=frame_h,
                )
            except Exception:
                frames_failed += 1
                log.exception("Navigation failure from %s frame %d", addr, frame_id)
                await websocket.send_text(json.dumps({
                    "frame_id": frame_id, "error": "Navigation failure",
                }))
                continue
            nav_ms = (time.perf_counter() - t_nav) * 1000.0

            # 4) normalise bboxes to 0-1 range for the client
            for ob in result["obstacles"]:
                x1, y1, x2, y2 = ob["bbox"]
                ob["bbox_px"] = [int(x1), int(y1), int(x2), int(y2)]
                ob["bbox"] = [
                    round(x1 / frame_w, 4), round(y1 / frame_h, 4),
                    round(x2 / frame_w, 4), round(y2 / frame_h, 4),
                ]
            # highest_priority is the same dict object as obstacles[0],
            # so it's already been normalised above — don't re-normalise.

            # 5) encode previews (if requested) 
            t_encode = time.perf_counter()
            if include_depth:
                hq = payload["hq"]
                depth_jpeg = _encode_depth_preview(depth_map, hq)
                yolo_jpeg = _encode_yolo_preview(frame, result["obstacles"], hq)
                freezone_jpeg = _encode_freezones_preview(frame, result["free_zones"], hq)
            else:
                depth_jpeg = yolo_jpeg = freezone_jpeg = None
            encode_ms = (time.perf_counter() - t_encode) * 1000.0

            total_ms = (time.perf_counter() - t_total) * 1000.0

            # 6) stats 
            timings.append({
                "decode_ms": decode_ms,
                "yolo_ms": yolo_ms,
                "depth_ms": depth_ms,
                "stairs_ms": stairs_ms,
                "nav_ms": nav_ms,
                "encode_ms": encode_ms,
                "total_ms": total_ms,
            })
            frames_processed += 1

            # 7) send JSON response
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
                        "stairs_ms": round(_rolling_avg(timings, "stairs_ms"), 2),
                        "nav_ms":    round(_rolling_avg(timings, "nav_ms"), 2),
                        "encode_ms": round(_rolling_avg(timings, "encode_ms"), 2),
                        "total_ms":  round(_rolling_avg(timings, "total_ms"), 2),
                    },
                    "frames_processed": frames_processed,
                    "frames_failed":    frames_failed,
                    "frames_skipped":   frames_skipped,
                    "frame_signature_mad": sig_mad,
                    "connection_uptime_s": round(time.perf_counter() - connection_t0, 1),
                },
                "device": DEVICE,
                "input_size": {"yolo": YOLO_INPUT_SIZE, "dav2": DAV2_INPUT_SIZE},
                "skipped": False,
                "depth_attached": depth_jpeg is not None,
                "yolo_attached": yolo_jpeg is not None,
                "freezone_attached": freezone_jpeg is not None,
            }
            # cache for frame-skip reuse
            last_response = response

            await websocket.send_text(json.dumps(response))

            # send preview images as binary messages
            for jpeg, flag in (
                (depth_jpeg, DEPTH_FLAG),
                (yolo_jpeg, YOLO_FLAG),
                (freezone_jpeg, FREEZONE_FLAG),
            ):
                if jpeg is not None:
                    header = frame_id.to_bytes(4, "big") + bytes([flag])
                    await websocket.send_bytes(header + jpeg)

            # 8) periodic log
            if frames_processed % LOG_EVERY_N_FRAMES == 0:
                log.info(
                    "[%s] frames=%d failed=%d skipped=%d fps=%.1f "
                    "decode=%.1fms yolo=%.1fms depth=%.1fms stairs=%.1fms nav=%.1fms total=%.1fms",
                    addr, frames_processed, frames_failed, frames_skipped,
                    1000.0 / _rolling_avg(timings, "total_ms"),
                    _rolling_avg(timings, "decode_ms"),
                    _rolling_avg(timings, "yolo_ms"),
                    _rolling_avg(timings, "depth_ms"),
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


# Raw-depth endpoint (for calibration data collection)
@app.websocket("/ws/raw_depth")
async def raw_depth_ws(websocket: WebSocket) -> None:
    """Returns uncalibrated per-obstacle depth for building calibration tables.
    Same wire format as /ws/avoidance. Runs YOLO + stairs + depth, returns
    the median raw depth of each detection's centre patch."""
    await websocket.accept()
    addr = f"{websocket.client.host}:{websocket.client.port}"
    log.info("Client connected: %s [/ws/raw_depth]", addr)

    if _yolo_detector is None or _dav2_model is None:
        await websocket.send_text(json.dumps({
            "error": "Models not loaded on the server (see /health)",
        }))
        await websocket.close(code=1011)
        return

    loop = asyncio.get_running_loop()
    try:
        while True:
            # receive + decode
            try:
                message = await websocket.receive()
                payload = _decode_frame_message(message)
            except WebSocketDisconnect:
                raise
            except Exception as exc:
                await websocket.send_text(json.dumps({"error": f"Bad frame: {exc}"}))
                continue

            try:
                frame = _decode_bgr_frame(payload["frame_bytes"])
            except Exception as exc:
                await websocket.send_text(json.dumps({
                    "frame_id": payload.get("frame_id", 0),
                    "error": f"Decode failure: {exc}",
                }))
                continue

            frame_id = payload["frame_id"]
            frame_h, frame_w = frame.shape[:2]

            # run models 
            try:
                depth_future = loop.run_in_executor(_executor, _run_depth, frame)
                yolo_future = loop.run_in_executor(_executor, _run_yolo, frame.copy())
                stairs_future = (loop.run_in_executor(_executor, _run_stairs, frame.copy())
                                 if _stairs_detector is not None else None)
                depth_map, depth_ms = await depth_future
                detections, yolo_ms = await yolo_future
                stairs_dets, stairs_ms = (
                    await stairs_future if stairs_future is not None else ([], 0.0)
                )
            except Exception:
                log.exception("Inference failure (raw_depth) from %s frame %d",
                              addr, frame_id)
                await websocket.send_text(json.dumps({
                    "frame_id": frame_id, "error": "Inference failure",
                }))
                continue

            # raw depth per detection
            out: list[dict] = []
            for d in detections + stairs_dets:
                bbox = d["bbox"]
                raw = obstacle_patch_depth(depth_map, bbox, frame_w, frame_h, d["label"])
                cx = (float(bbox[0]) + float(bbox[2])) / 2.0
                region = ("LEFT" if cx < frame_w * 0.34
                          else "RIGHT" if cx > frame_w * 0.66 else "CENTRE")
                out.append({
                    "label": d["label"],
                    "confidence": d["confidence"],
                    "bbox": [int(round(float(v))) for v in bbox],
                    "region": region,
                    "raw_depth_m": round(raw, 3) if raw is not None else None,
                })

            await websocket.send_text(json.dumps({
                "frame_id": frame_id,
                "frame_size": {"w": frame_w, "h": frame_h},
                "detections": out,
                "metrics": {
                    "yolo_ms": round(yolo_ms, 2),
                    "depth_ms": round(depth_ms, 2),
                    "stairs_ms": round(stairs_ms, 2),
                },
                "device": DEVICE,
                "calibrated": False,
            }))

    except WebSocketDisconnect:
        log.info("Client disconnected: %s [/ws/raw_depth]", addr)
    except Exception:
        log.error("Unhandled error (raw_depth) from %s\n%s", addr, traceback.format_exc())
        try:
            await websocket.send_text(json.dumps({"error": "Server error"}))
        except Exception:
            pass


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
