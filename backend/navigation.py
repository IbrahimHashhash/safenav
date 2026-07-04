import time

import numpy as np

# this file contains the 'navigation' logic for the server code.
# it processes the output of the two models (yolo and DAV2) and generates
# the avoidance instruction.
#
# inputs : yolo detections, depth map, frame size, tracker state
# process: per-detection metric depth → region/urgency → temporal track
#          → free-zone analysis on the forward corridor → highest-priority
#          obstacle → natural-language instruction
# output : one instruction per call (typically 1-3 frames)


# --------------------------------------------------------------------------- #
# tunables
# --------------------------------------------------------------------------- #
_EM_DASH = "\u2014"

# distance buckets (metres)
_DIST_CRITICAL_M = 1.5
_DIST_HIGH_M = 3.0
_DIST_MEDIUM_M = 5.0   # campus feedback: max obstacle distance is 5 m (was 6)

# free-zone analysis
_FREE_THRESHOLD_M = 2.5      # zones with clearance >= this (calibrated real m) are walkable
# free-zone band: a HORIZON-CENTRED slice. SAM ground filtering was removed, so
# we now avoid the ground plane geometrically -- exclude the lower part of the
# frame (ground, for a chest/head-height forward-facing camera) and the upper
# part (sky / ceiling / overhead), keeping the band around the horizon where
# obstacle bodies cross it. Tune these to the camera pitch on real footage.
_ZONE_NAMES = ("left", "slight_left", "centre", "slight_right", "right")
_BAND_TOP_FRAC = 0.15        # exclude the top 15% (sky / ceiling / overhead)
_BAND_BOTTOM_FRAC = 0.60     # exclude the bottom 40% -- any higher values ( > 0.55) will cause mis-interpretation and consider clear paths as blocked
_FREE_PERCENTILE = 5.0       # 5th-percentile = closest robust surface

# tracker
_IOU_MATCH_THRESHOLD = 0.4
_HISTORY_LEN = 5
_ANNOUNCE_COOLDOWN_S = 3.0

# fast-passing-person skip (campus feedback #6): a person that was close on the
# edge of the frame and is now receding is walking past, not an obstacle to
# avoid -- drop it so we don't nag the user about people who already passed.
_SKIP_PASSING_PERSON = True
_PASS_NEAR_M = 2.5          # "was close" threshold (earliest tracked distance)
_PASS_RECEDE_DELTA_M = 1.0  # must have receded at least this far since then
_PASS_MIN_HISTORY = 3       # need a few frames of history to be confident


# --------------------------------------------------------------------------- #
# helpers (module-level so they aren't rebuilt per call)
# --------------------------------------------------------------------------- #
def _compute_iou(box_a, box_b) -> float:
    """Standard intersection-over-union for two [x1,y1,x2,y2] boxes."""
    ax1, ay1, ax2, ay2 = box_a
    bx1, by1, bx2, by2 = box_b
    inter_w = max(0.0, min(ax2, bx2) - max(ax1, bx1))
    inter_h = max(0.0, min(ay2, by2) - max(ay1, by1))
    inter = inter_w * inter_h
    area_a = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1)
    area_b = max(0.0, bx2 - bx1) * max(0.0, by2 - by1)
    union = area_a + area_b - inter
    return inter / union if union > 0.0 else 0.0


def _best_walkable_side(free_zones: dict) -> str | None:
    """
    Decide the safest detour direction from the per-zone clearance.

    Returns one of "left", "slightly left", "right", "slightly right",
    or None when neither side is walkable.
    """
    l = free_zones["left"]["clearance_m"]
    sl = free_zones["slight_left"]["clearance_m"]
    sr = free_zones["slight_right"]["clearance_m"]
    r = free_zones["right"]["clearance_m"]

    left_best = max(l, sl)
    right_best = max(r, sr)

    if left_best < _FREE_THRESHOLD_M and right_best < _FREE_THRESHOLD_M:
        return None

    # prefer the side with more room; within a side prefer the wider angle
    # ("left") over the narrower one ("slightly left").
    if left_best >= right_best:
        return "left" if l >= sl else "slightly left"
    return "right" if r >= sr else "slightly right"


def init_tracker_state() -> dict:
    return {"tracks": [], "next_id": 0, "last_announced": {}}


# depth calibration (campus feedback #4): the metric model under-reports
# distance, increasingly so with range (real 3 m reads ~2.3 m, real 4 m reads
# ~3.1 m). These anchors map ESTIMATED -> REAL metres. Close range (<= 1.5 m) is
# left as identity so we never over-report an imminent obstacle (which would be
# unsafe), and beyond the last anchor we extrapolate with the last segment slope.
_CAL_EST = np.array([0.0, 1.5, 2.3, 3.1], dtype=float)   # estimated metres
_CAL_REAL = np.array([0.0, 1.5, 3.0, 4.0], dtype=float)  # corresponding real metres
_CAL_RIGHT_SLOPE = (_CAL_REAL[-1] - _CAL_REAL[-2]) / (_CAL_EST[-1] - _CAL_EST[-2])


def est_to_real_depth(est):
    """Map the model's estimated metric depth to calibrated real metres."""
    est = np.asarray(est, dtype=float)
    real = np.interp(est, _CAL_EST, _CAL_REAL)
    # linear extrapolation past the furthest anchor (np.interp would clamp it)
    real = np.where(
        est > _CAL_EST[-1],
        _CAL_REAL[-1] + _CAL_RIGHT_SLOPE * (est - _CAL_EST[-1]),
        real,
    )
    return real


# --------------------------------------------------------------------------- #
# main pipeline
# --------------------------------------------------------------------------- #
def run_detection_pipeline(
    yolo_detections: list[dict],
    depth_map: np.ndarray,
    frame_w: int,
    frame_h: int,
    tracker_state: dict,    # the system's memory -- AI would be 'forgetful' without it
) -> dict:

    if frame_w <= 0 or frame_h <= 0:
        raise ValueError("frame_w and frame_h must be positive")

    # data sanitisation:
    # converting data type to float32 for precision;
    # depth models usually output float16 to save memory.
    depth = np.asarray(depth_map, dtype=np.float32)
    if depth.ndim != 2:
        raise ValueError("depth_map must be a 2D array")
    # ensure any NaN / +-inf are converted to zero.
    depth = np.nan_to_num(depth, nan=0.0, posinf=0.0, neginf=0.0)

    dh, dw = depth.shape  # depth_height, depth_width

    if not isinstance(tracker_state, dict):
        raise ValueError("tracker_state must be a dict (use init_tracker_state())")
    tracker_state.setdefault("tracks", [])
    tracker_state.setdefault("next_id", 0)
    tracker_state.setdefault("last_announced", {})

    # snapshot of all objects detected in the previous frame -- used as a
    # reference list to compare against new detections via IoU.
    previous_tracks = list(tracker_state["tracks"])

    # one identity → one detection. once a previous track has been claimed
    # by a new detection we mark its id here so it can't be claimed again.
    matched_track_ids: set[int] = set()

    # the new memory built for the current frame.
    updated_tracks: list[dict] = []
    obstacles: list[dict] = []
    current_time = time.time()

    for detection in yolo_detections or []:
        bbox = detection.get("bbox", [0, 0, 0, 0])
        x1, y1, x2, y2 = (float(v) for v in bbox)

        # defensive programming: ensure (x1,y1) is top-left and
        # (x2,y2) is bottom-right regardless of the model's output order.
        x1, x2 = sorted((x1, x2))
        y1, y2 = sorted((y1, y2))

        bbox_pixels = [int(round(x1)), int(round(y1)),
                       int(round(x2)), int(round(y2))]

        label = str(detection.get("label", "")).lower()
        confidence = float(detection.get("confidence", 0.0))
        box_centre_x = (x1 + x2) / 2.0
        box_centre_y = (y1 + y2) / 2.0

        # STEP 1 -- scale the bbox to depth-map coordinates and shrink to
        # a 50 % centre patch so the depth sample is dominated by the
        # object surface rather than its background edges.
        depth_x1 = max(0, min(dw - 1, int(x1 * dw / frame_w)))
        depth_y1 = max(0, min(dh - 1, int(y1 * dh / frame_h)))
        depth_x2 = max(0, min(dw - 1, int(x2 * dw / frame_w)))
        depth_y2 = max(0, min(dh - 1, int(y2 * dh / frame_h)))

        dx = (depth_x2 - depth_x1) * 0.25
        dy = (depth_y2 - depth_y1) * 0.25
        inner_x1 = max(0, min(dw - 1, int(depth_x1 + dx)))
        inner_x2 = max(0, min(dw - 1, int(depth_x2 - dx)))
        inner_y1 = max(0, min(dh - 1, int(depth_y1 + dy)))
        inner_y2 = max(0, min(dh - 1, int(depth_y2 - dy)))
        if inner_x2 < inner_x1:
            inner_x1, inner_x2 = inner_x2, inner_x1
        if inner_y2 < inner_y1:
            inner_y1, inner_y2 = inner_y2, inner_y1

        depth_region = depth[inner_y1:inner_y2 + 1, inner_x1:inner_x2 + 1]
        if depth_region.size == 0:
            # degenerate / off-screen box -- skip rather than emit garbage
            continue
        
        # calibrated metric distance (see est_to_real_depth / campus feedback #4)
        distance_m = float(est_to_real_depth(float(np.median(depth_region))))

        # STEP 2 -- assign LEFT/RIGHT/CENTRE from the bbox's frame x-centre.
        if box_centre_x < frame_w * 0.34:
            region = "LEFT"
        elif box_centre_x > frame_w * 0.66:
            region = "RIGHT"
        else:
            region = "CENTRE"

        # STEP 3 -- bucket by metric distance.
        if distance_m < _DIST_CRITICAL_M:
            urgency, distance_label = "CRITICAL", "right ahead"
        elif distance_m < _DIST_HIGH_M:
            urgency, distance_label = "HIGH", "close"
        elif distance_m < _DIST_MEDIUM_M:
            urgency, distance_label = "MEDIUM", "ahead"
        else:
            urgency, distance_label = "LOW", None

        # STEP 4 -- assign a stable track_id via IoU against the previous frame.
        # (Motion/approach analysis was removed per campus feedback #4; we keep
        # only the depth history needed for the cooldown and the passing-person
        # skip.)
        best_track = None
        best_iou = 0.0
        for track in previous_tracks:
            track_id = int(track.get("track_id", -1))
            if track_id in matched_track_ids:
                continue
            iou = _compute_iou(
                [x1, y1, x2, y2],
                list(track.get("bbox", [0, 0, 0, 0])),
            )
            if iou > best_iou:
                best_iou = iou
                best_track = track

        if best_track is not None and best_iou >= _IOU_MATCH_THRESHOLD:
            track_id = int(best_track["track_id"])
            distance_history = list(best_track.get("distance_history", []))
            matched_track_ids.add(track_id)
        else:
            track_id = int(tracker_state["next_id"])
            tracker_state["next_id"] = track_id + 1
            distance_history = []

        # update depth history (cap at _HISTORY_LEN entries)
        distance_history = (distance_history + [distance_m])[-_HISTORY_LEN:]
        updated_tracks.append({
            "track_id": track_id,
            "bbox": bbox_pixels,
            "distance_history": distance_history,
        })

        # campus feedback #6 -- skip a person who was close on the edge and is
        # now receding (they are walking past, not an obstacle ahead). We still
        # track them (above), we just don't announce them.
        if (_SKIP_PASSING_PERSON and label == "person"
                and region in ("LEFT", "RIGHT")
                and len(distance_history) >= _PASS_MIN_HISTORY
                and distance_history[0] <= _PASS_NEAR_M
                and distance_m - distance_history[0] >= _PASS_RECEDE_DELTA_M):
            continue

        # STEP 5 -- priority score; LOW obstacles are dropped from output.
        base_score = {"CRITICAL": 100, "HIGH": 70, "MEDIUM": 40, "LOW": 0}[urgency]
        region_modifier = 20 if region == "CENTRE" else 5
        cooldown_modifier = 0
        last_announced = tracker_state["last_announced"]
        if (track_id in last_announced
                and current_time - float(last_announced[track_id]) < _ANNOUNCE_COOLDOWN_S):
            cooldown_modifier = -50
        priority_score = int(base_score + region_modifier + cooldown_modifier)

        if urgency != "LOW":
            obstacles.append({
                "label": label,
                "bbox": bbox_pixels,
                "confidence": confidence,
                "distance_m": round(distance_m, 2),
                "depth": round(distance_m, 2),  # alias so clients reading 'depth' get it too
                "region": region,
                "urgency": urgency,
                "distance_label": distance_label,
                "track_id": track_id,
                "priority_score": priority_score,
            })

    tracker_state["tracks"] = updated_tracks

    # STEP 6 -- precise free-zone analysis.
    # Sample a HORIZON-CENTRED slice of the forward walking corridor:
    #   • exclude the top of the frame (ceiling / sky / distant background)
    #   • exclude the bottom of the frame -- this is the GROUND plane for a
    #     chest/head-height forward camera. We drop it geometrically here
    #     instead of relying on SAM ground segmentation (which was unreliable),
    #     so the close floor never falsely flags every zone as blocked.
    # Split the corridor into 5 vertical zones for finer-grained guidance
    # (left, slight_left, centre, slight_right, right) and use the
    # 5th-percentile of valid depths in each zone as the "closest robust
    # surface". This is far more noise-tolerant than np.min, which can
    # be ruined by a single bad pixel.
    band_top = int(dh * _BAND_TOP_FRAC)
    band_bot = int(dh * _BAND_BOTTOM_FRAC)
    forward_band = depth[band_top:band_bot, :]
    zone_edges = np.linspace(0, dw, len(_ZONE_NAMES) + 1, dtype=int)

    free_zones: dict[str, dict] = {}
    for idx, name in enumerate(_ZONE_NAMES):
        column = forward_band[:, zone_edges[idx]:zone_edges[idx + 1]]
        if column.size == 0:
            clearance = 0.0
        else:
            valid = column[column > 0.0]
            raw_clearance = (float(np.percentile(valid, _FREE_PERCENTILE))
                             if valid.size else 0.0)
            # calibrate to real metres (same mapping as the per-obstacle distance)
            clearance = (float(est_to_real_depth(raw_clearance))
                         if raw_clearance > 0.0 else 0.0)
        free_zones[name] = {
            "clear": clearance >= _FREE_THRESHOLD_M,
            "clearance_m": round(clearance, 2),
        }

    # STEP 7 -- pick the single highest-priority obstacle.
    obstacles.sort(key=lambda o: o["priority_score"], reverse=True)
    highest_priority = obstacles[0] if obstacles else None

    # STEP 8 -- generate the (descriptive-only) instruction.
    # Campus feedback #1: report obstacle info + which side is clear, with NO
    # action words ("step", "veer", "continue ahead", ...). Examples:
    #   "Path clear."   |   "car ahead 3.0 m — left clear"
    if highest_priority is None:
        instruction = "Path clear."
    else:
        label = highest_priority["label"] or "obstacle"
        region = highest_priority["region"]
        distance_m = highest_priority["distance_m"]

        position = ("ahead" if region == "CENTRE"
                    else "on left" if region == "LEFT" else "on right")

        left_clear = (free_zones["left"]["clear"]
                      or free_zones["slight_left"]["clear"])
        right_clear = (free_zones["right"]["clear"]
                       or free_zones["slight_right"]["clear"])
        centre_clear = free_zones["centre"]["clear"]

        # Report only the directions AWAY from the obstacle: the centre and the
        # opposite side for a side obstacle, or both sides for a centre obstacle.
        # Never claim the obstacle's own side is clear (that would be nonsense,
        # e.g. "car on right -- right clear").
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

        tracker_state["last_announced"][highest_priority["track_id"]] = current_time

    return {
        "instruction": instruction,
        "obstacles": obstacles,
        "free_zones": free_zones,
        "highest_priority": highest_priority,
    }
