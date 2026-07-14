import numpy as np

# navigation logic — takes YOLO detections + depth map and produces
# an avoidance instruction like "car ahead 3.0 m — left clear".


_EM_DASH = "\u2014"

# distance buckets (metres)
_DIST_CRITICAL_M = 1.5
_DIST_HIGH_M = 3.0
_DIST_MEDIUM_M = 5.0

# free-zone analysis
_FREE_THRESHOLD_M = 2.5  # a zone needs at least this much clearance to be "walkable"
_ZONE_NAMES = ("left", "slight_left", "centre", "slight_right", "right")
_BAND_TOP_FRAC = 0.15   # skip the top 15% of the depth map (sky/ceiling)
_BAND_BOTTOM_FRAC = 0.60  # skip below 60% (ground plane)
_FREE_PERCENTILE = 5.0   # use 5th percentile as the "closest real surface"


# helpers
def _best_walkable_side(free_zones: dict) -> str | None:
    """Pick the side with the most room, or None if both sides are blocked."""
    l = free_zones["left"]["clearance_m"]
    sl = free_zones["slight_left"]["clearance_m"]
    sr = free_zones["slight_right"]["clearance_m"]
    r = free_zones["right"]["clearance_m"]

    left_best = max(l, sl)
    right_best = max(r, sr)

    if left_best < _FREE_THRESHOLD_M and right_best < _FREE_THRESHOLD_M:
        return None

    if left_best >= right_best:
        return "left" if l >= sl else "slightly left"
    return "right" if r >= sr else "slightly right"


# per-class depth calibration
# the depth model is inaccurate, and the error depends on what it's looking at.
# these tables map model estimates -> real distances (from tape-measure tests).
# format: (estimates_ascending[], real_distances[])
_CALIBRATION: dict[str, tuple[list[float], list[float]]] = {
    "person": (
        [1.46, 1.74, 2.59, 3.06, 3.50, 4.62, 4.91, 5.27, 5.73],
        [1.0,  1.5,  2.0,  2.5,  3.0,  3.5,  4.0,  4.5,  5.0],
    ),
    "car": (
        [0.86, 1.33, 1.79, 2.15, 2.71, 3.08, 3.37, 3.65, 3.86],
        [1.0,  1.5,  2.0,  2.5,  3.0,  3.5,  4.0,  4.5,  5.0],
    ),
    "bench": (
        [1.86, 1.90, 2.42, 2.96, 3.36, 3.73, 4.38, 4.47, 4.81],
        [1.5,  1.0,  2.0,  2.5,  3.0,  3.5,  4.0,  4.5,  5.0],
    ),
    "stairs": (
        [1.40, 1.45, 1.55, 2.65, 3.23, 3.70, 4.13, 4.75],
        [1.0,  2.0,  2.5,  3.0,  3.5,  4.0,  4.5,  5.0],
    ),
}
_MAX_CALIBRATED_M = 12.0  # cap extrapolation so noise doesn't produce crazy values


def est_to_real_depth(est, label: str | None = None):
    """Convert model's estimated depth to calibrated real metres.
    Uses the per-class table if available, otherwise returns raw depth."""
    est = np.asarray(est, dtype=float)

    # if we don't have a calibration table for this class, just use raw values
    key = str(label).lower() if label else ""
    if key not in _CALIBRATION:
        return np.clip(est, 0.0, _MAX_CALIBRATED_M)

    xp_list, fp_list = _CALIBRATION[key]
    xp = np.asarray(xp_list, dtype=float)
    fp = np.asarray(fp_list, dtype=float)

    real = np.interp(est, xp, fp)
    # np.interp clamps outside the table — extrapolate linearly instead
    left_slope = (fp[1] - fp[0]) / (xp[1] - xp[0])
    right_slope = (fp[-1] - fp[-2]) / (xp[-1] - xp[-2])
    real = np.where(est < xp[0], fp[0] + left_slope * (est - xp[0]), real)
    real = np.where(est > xp[-1], fp[-1] + right_slope * (est - xp[-1]), real)
    return np.clip(real, 0.0, _MAX_CALIBRATED_M)


def obstacle_patch_depth(depth, bbox, frame_w: int, frame_h: int, label=None):
    """Get the median depth from inside an obstacle's bounding box.
    Samples the inner 50% to avoid background pixels at the edges.
    For stairs, samples the bottom third (nearest step)."""
    dh, dw = depth.shape
    x1, x2 = sorted((float(bbox[0]), float(bbox[2])))
    y1, y2 = sorted((float(bbox[1]), float(bbox[3])))

    # map frame coords to depth map coords
    dx1 = max(0, min(dw - 1, int(x1 * dw / frame_w)))
    dy1 = max(0, min(dh - 1, int(y1 * dh / frame_h)))
    dx2 = max(0, min(dw - 1, int(x2 * dw / frame_w)))
    dy2 = max(0, min(dh - 1, int(y2 * dh / frame_h)))

    # shrink horizontally to inner 50%
    sx = (dx2 - dx1) * 0.25
    ix1 = max(0, min(dw - 1, int(dx1 + sx)))
    ix2 = max(0, min(dw - 1, int(dx2 - sx)))

    if str(label).lower() == "stairs":
        # bottom third only (the nearest step is what matters)
        iy1 = max(0, min(dh - 1, int(dy1 + (dy2 - dy1) * (2.0 / 3.0))))
        iy2 = dy2
    else:
        # inner 50% vertically
        sy = (dy2 - dy1) * 0.25
        iy1 = max(0, min(dh - 1, int(dy1 + sy)))
        iy2 = max(0, min(dh - 1, int(dy2 - sy)))

    # safety swap in case coords crossed (very small boxes)
    if ix2 < ix1:
        ix1, ix2 = ix2, ix1
    if iy2 < iy1:
        iy1, iy2 = iy2, iy1

    patch = depth[iy1:iy2 + 1, ix1:ix2 + 1]
    if patch.size == 0:
        return None
    return float(np.median(patch))


# main pipeline
def run_detection_pipeline(
    yolo_detections: list[dict],
    depth_map: np.ndarray,
    frame_w: int,
    frame_h: int,
) -> dict:

    if frame_w <= 0 or frame_h <= 0:
        raise ValueError("frame_w and frame_h must be positive")

    # convert to float32 (depth model may output float16) and clean up bad values
    depth = np.asarray(depth_map, dtype=np.float32)
    if depth.ndim != 2:
        raise ValueError("depth_map must be a 2D array")
    depth = np.nan_to_num(depth, nan=0.0, posinf=0.0, neginf=0.0)

    dh, dw = depth.shape

    obstacles: list[dict] = []

    for detection in yolo_detections or []:
        bbox = detection.get("bbox", [0, 0, 0, 0])
        x1, y1, x2, y2 = (float(v) for v in bbox)

        # make sure top-left < bottom-right
        x1, x2 = sorted((x1, x2))
        y1, y2 = sorted((y1, y2))

        bbox_pixels = [int(round(x1)), int(round(y1)),
                       int(round(x2)), int(round(y2))]

        label = str(detection.get("label", "")).lower()
        confidence = float(detection.get("confidence", 0.0))
        box_centre_x = (x1 + x2) / 2.0
        box_centre_y = (y1 + y2) / 2.0

        # STEP 1 — get this obstacle's depth
        raw_depth = obstacle_patch_depth(depth, [x1, y1, x2, y2],
                                         frame_w, frame_h, label)
        if raw_depth is None:
            continue

        # calibrate if we have a table for this class, otherwise use raw
        distance_m = float(est_to_real_depth(raw_depth, label))

        # STEP 2 — which side of the frame is it on?
        if box_centre_x < frame_w * 0.34:
            region = "LEFT"
        elif box_centre_x > frame_w * 0.66:
            region = "RIGHT"
        else:
            region = "CENTRE"

        # STEP 3 — how urgent is it?
        if distance_m < _DIST_CRITICAL_M:
            urgency, distance_label = "CRITICAL", "right ahead"
        elif distance_m < _DIST_HIGH_M:
            urgency, distance_label = "HIGH", "close"
        elif distance_m < _DIST_MEDIUM_M:
            urgency, distance_label = "MEDIUM", "ahead"
        else:
            urgency, distance_label = "LOW", None

        # STEP 4 — priority score (centre obstacles rank higher); drop LOW
        base_score = {"CRITICAL": 100, "HIGH": 70, "MEDIUM": 40, "LOW": 0}[urgency]
        region_modifier = 20 if region == "CENTRE" else 5
        priority_score = int(base_score + region_modifier)

        if urgency != "LOW":
            obstacles.append({
                "label": label,
                "bbox": bbox_pixels,
                "confidence": confidence,
                "distance_m": round(distance_m, 2),
                "depth": round(distance_m, 2),
                "region": region,
                "urgency": urgency,
                "distance_label": distance_label,
                "priority_score": priority_score,
            })


    # STEP 5 — free-zone analysis: which directions are clear to walk?
    # look at a horizontal band around the horizon (skip sky above, ground below)
    # and split it into 5 lanes. use the 5th percentile depth per lane as the
    # closest surface (robust to noisy pixels).
    band_top = int(dh * _BAND_TOP_FRAC)
    band_bot = int(dh * _BAND_BOTTOM_FRAC)
    forward_band = depth[band_top:band_bot, :]
    zone_edges = np.linspace(0, dw, len(_ZONE_NAMES) + 1, dtype=int)

    # build obstacle horizontal spans so we can veto lanes they occupy
    obs_spans = []
    for o in obstacles:
        ox1, _oy1, ox2, _oy2 = o["bbox"]
        sx1 = ox1 * dw / frame_w
        sx2 = ox2 * dw / frame_w
        obs_spans.append((min(sx1, sx2), max(sx1, sx2), o["distance_m"]))

    free_zones: dict[str, dict] = {}
    for idx, name in enumerate(_ZONE_NAMES):
        lane_x1, lane_x2 = int(zone_edges[idx]), int(zone_edges[idx + 1])
        column = forward_band[:, lane_x1:lane_x2]
        if column.size == 0:
            clearance = 0.0
        else:
            valid = column[column > 0.0]
            raw_clearance = (float(np.percentile(valid, _FREE_PERCENTILE))
                             if valid.size else 0.0)
            # use raw depth for free-zone (no calibration for empty space)
            clearance = raw_clearance if raw_clearance > 0.0 else 0.0

        # if a detected obstacle overlaps this lane, cap the clearance
        # (depth model is unreliable on obstacle surfaces — can read too far)
        overlap = [d for (sx1, sx2, d) in obs_spans
                   if sx2 > lane_x1 and sx1 < lane_x2]
        occupied = bool(overlap)
        if occupied:
            od = min(overlap)
            clearance = od if clearance <= 0.0 else min(clearance, od)

        free_zones[name] = {
            "clear": (clearance >= _FREE_THRESHOLD_M) and not occupied,
            "clearance_m": round(clearance, 2),
        }

    # STEP 6 — pick the most important obstacle
    obstacles.sort(key=lambda o: o["priority_score"], reverse=True)
    highest_priority = obstacles[0] if obstacles else None

    # if stairs are present, don't suggest directions (could send user toward them)
    stairs_detected = any(o.get("label") == "stairs" for o in obstacles)

    # STEP 7 — build the instruction text
    # just report what's there + which side is clear, no action words
    if highest_priority is None:
        # no YOLO detection, but depth might still show something blocking ahead
        if free_zones["centre"]["clear"]:
            instruction = "Path clear."
        else:
            left_clear = (free_zones["left"]["clear"]
                          or free_zones["slight_left"]["clear"])
            right_clear = (free_zones["right"]["clear"]
                           or free_zones["slight_right"]["clear"])
            clear_names = [n for n, ok in (("left", left_clear),
                                           ("right", right_clear)) if ok]
            if clear_names:
                instruction = (f"Path likely blocked ahead {_EM_DASH} "
                               f"{' and '.join(clear_names)} clear")
            else:
                instruction = "Path likely blocked ahead."
    else:
        label = highest_priority["label"] or "obstacle"
        region = highest_priority["region"]
        distance_m = highest_priority["distance_m"]

        position = ("ahead" if region == "CENTRE"
                    else "on left" if region == "LEFT" else "on right")

        if stairs_detected:
            instruction = f"{label} {position} {distance_m:.1f} m"
        else:
            left_clear = (free_zones["left"]["clear"]
                          or free_zones["slight_left"]["clear"])
            right_clear = (free_zones["right"]["clear"]
                           or free_zones["slight_right"]["clear"])
            centre_clear = free_zones["centre"]["clear"]

            # only suggest directions AWAY from the obstacle
            if region == "LEFT":
                candidates = (("centre", centre_clear), ("right", right_clear))
            elif region == "RIGHT":
                candidates = (("centre", centre_clear), ("left", left_clear))
            else:  # CENTRE
                candidates = (("left", left_clear), ("right", right_clear))

            clear_names = [name for name, ok in candidates if ok]
            clearance = (" and ".join(clear_names) + " clear"
                         if clear_names else "no clear path")

            instruction = f"{label} {position} {distance_m:.1f} m {_EM_DASH} {clearance}"

    return {
        "instruction": instruction,
        "obstacles": obstacles,
        "free_zones": free_zones,
        "highest_priority": highest_priority,
    }
