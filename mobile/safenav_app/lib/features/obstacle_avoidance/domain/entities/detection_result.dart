import 'dart:typed_data';

/// One vertical free-zone region from the server's `free_zones` analysis.
/// [free] true = clear (green), false = blocked (red). [clearanceM] is the
/// estimated clear distance for the region in meters, when provided. Regions
/// are ordered left-to-right across the analysis band.
class FreeZone {
  final bool free;
  final double? clearanceM;

  /// Human label for the region (e.g. "Slight left"), when the server keys the
  /// zones by name. Null for positional/list shapes.
  final String? label;

  const FreeZone(this.free, {this.clearanceM, this.label});
}

/// Parses the server's `free_zones` field into ordered [FreeZone]s.
///
/// Tolerant of the shapes the navigation pipeline might emit:
///  - region-keyed map (current server):
///    `{"left": {"clear": false, "clearance_m": 0.86}, "slight_left": {...},
///      "centre": {...}, "slight_right": {...}, "right": {...}}`
///  - list of bools:           `[true, false, true, true, false]`
///  - list of objects:         `[{"clear": true, "clearance_m": 2.3}, ...]`
///  - list of FREE indices:    `[0, 2, 4]` (interpreted over 5 regions)
List<FreeZone> parseFreeZones(dynamic raw, {int regionCount = 5}) {
  if (raw is Map) {
    // Wrapper object that holds a list under a known key.
    for (final k in ['regions', 'zones', 'free_zones', 'bands', 'items']) {
      if (raw[k] is List) {
        return parseFreeZones(raw[k], regionCount: regionCount);
      }
    }
    // Region-keyed map: {left: {...}, slight_left: {...}, ...}.
    if (raw.values.any((v) => v is Map)) {
      return _parseRegionMap(raw);
    }
    return const [];
  }

  if (raw is! List || raw.isEmpty) return const [];

  // All-numeric -> indices of the free regions.
  if (raw.every((e) => e is num)) {
    final freeIdx = raw.map((e) => (e as num).toInt()).toSet();
    return List.generate(regionCount, (i) => FreeZone(freeIdx.contains(i)));
  }

  final out = <FreeZone>[];
  for (final e in raw) {
    if (e is bool) {
      out.add(FreeZone(e));
    } else if (e is Map) {
      out.add(FreeZone(_zoneIsFree(e),
          clearanceM: _zoneClearance(e), label: _zoneLabel(e)));
    } else if (e is List) {
      out.add(_zoneFromList(e));
    }
  }
  return out;
}

/// Canonical left-to-right region order for the named-region map.
const List<String> _regionOrder = [
  'left',
  'slight_left',
  'slightleft',
  'centre',
  'center',
  'middle',
  'slight_right',
  'slightright',
  'right',
];

List<FreeZone> _parseRegionMap(Map raw) {
  final out = <FreeZone>[];
  final used = <String>{};

  String pretty(String k) {
    final s = k.replaceAll('_', ' ').trim();
    return s.isEmpty ? k : '${s[0].toUpperCase()}${s.substring(1)}';
  }

  // Known regions first, in left-to-right order.
  for (final key in _regionOrder) {
    final v = raw[key];
    if (v is Map && !used.contains(key)) {
      used.add(key);
      out.add(FreeZone(_zoneIsFree(v),
          clearanceM: _zoneClearance(v), label: pretty(key)));
    }
  }
  // Any remaining map entries, in insertion order.
  raw.forEach((k, v) {
    final key = k.toString();
    if (v is Map && !used.contains(key)) {
      used.add(key);
      out.add(FreeZone(_zoneIsFree(v),
          clearanceM: _zoneClearance(v), label: pretty(key)));
    }
  });
  return out;
}

String? _zoneLabel(Map e) {
  final l = e['label'] ?? e['name'] ?? e['region'];
  return l is String ? l : null;
}

FreeZone _zoneFromList(List e) {
  bool free = false;
  double? clearance;
  for (final v in e) {
    if (v is bool) free = v;
    if (v is num) clearance ??= v.toDouble();
  }
  return FreeZone(free, clearanceM: clearance);
}

double? _zoneClearance(Map e) {
  for (final k in [
    'clearance_m',
    'clearance',
    'clear_m',
    'free_distance_m',
    'distance_m',
    'depth_m',
  ]) {
    if (e[k] is num) return (e[k] as num).toDouble();
  }
  return null;
}

bool _zoneIsFree(Map e) {
  for (final k in ['free', 'is_free', 'isFree', 'clear']) {
    if (e[k] is bool) return e[k] as bool;
  }
  for (final k in ['blocked', 'occupied', 'is_blocked', 'isBlocked']) {
    if (e[k] is bool) return !(e[k] as bool);
  }
  final status = e['status'] ?? e['state'];
  if (status is String) {
    final s = status.toLowerCase();
    return s == 'free' || s == 'clear' || s == 'open';
  }
  return false;
}

/// A single detected obstacle from the server's `obstacles` array.
class DetectedObstacle {
  final String label;
  final double confidence;

  /// Estimated distance in meters, when the server provides it. The depth
  /// model produces this; the exact JSON key can vary, so several are tried.
  final double? distanceMeters;

  /// Normalised bounding box [x1, y1, x2, y2] in 0..1 of the frame.
  final List<double> bbox;

  const DetectedObstacle({
    required this.label,
    required this.confidence,
    required this.distanceMeters,
    required this.bbox,
  });

  factory DetectedObstacle.fromJson(Map<String, dynamic> json) {
    double? num2(dynamic v) => v is num ? v.toDouble() : null;

    // Distance lives under different names depending on the server pipeline.
    final distance = num2(json['distance']) ??
        num2(json['distance_m']) ??
        num2(json['depth']) ??
        num2(json['depth_m']) ??
        num2(json['estimated_distance']);

    final rawBox = json['bbox'];
    final bbox = rawBox is List
        ? rawBox.map((e) => (e as num).toDouble()).toList()
        : <double>[];

    return DetectedObstacle(
      label: (json['label'] as String?) ?? 'object',
      confidence: num2(json['confidence']) ?? 0.0,
      distanceMeters: distance,
      bbox: bbox,
    );
  }
}

/// Server-side timing metrics for one processed frame.
///
/// Keeps the raw map (so every metric can be listed) plus typed accessors for
/// the common per-model timings.
class ServerMetrics {
  final Map<String, dynamic> raw;

  const ServerMetrics(this.raw);

  static const ServerMetrics empty = ServerMetrics({});

  double? _ms(String key) {
    final v = raw[key];
    return v is num ? v.toDouble() : null;
  }

  double? get decodeMs => _ms('decode_ms');
  double? get yoloMs => _ms('yolo_ms');
  double? get depthMs => _ms('depth_ms');
  double? get samMs => _ms('sam_ms');
  double? get stairsMs => _ms('stairs_ms');
  double? get navMs => _ms('nav_ms');
  double? get encodeMs => _ms('encode_ms');
  double? get totalMs => _ms('total_ms');
  double? get serverFps => _ms('server_fps');
  double? get rollingFps => _ms('rolling_fps');

  /// All scalar (num) metrics as label/value pairs, for a full listing.
  List<MapEntry<String, num>> get scalarEntries {
    final out = <MapEntry<String, num>>[];
    raw.forEach((key, value) {
      if (value is num) out.add(MapEntry(key, value));
    });
    return out;
  }
}

/// The full result for a single frame: the spoken instruction, detected
/// obstacles, server metrics, and (when previews were requested) the decoded
/// model preview images. [endToEndMs] is measured on the client.
class DetectionResult {
  final int frameId;
  final String instruction;
  final List<DetectedObstacle> obstacles;
  final List<FreeZone> freeZones;

  /// The raw `free_zones` value from the server, kept for diagnostics when the
  /// parser can't interpret its shape.
  final dynamic freeZonesRaw;

  final ServerMetrics metrics;
  final int? frameWidth;
  final int? frameHeight;
  final bool skipped;

  /// The obstacle the server flagged as highest priority (e.g. the blocking
  /// car), when present.
  final DetectedObstacle? highestPriority;

  /// Mean Absolute Difference vs. the previous processed frame (the server's
  /// frame-similarity signal). Lower = more similar; the server skips frames
  /// below its threshold. Null when the server doesn't report it.
  final double? mad;

  final bool depthAttached;
  final bool segAttached;
  final bool yoloAttached;
  final bool maskAttached;

  // Preview image bytes, filled in as binary messages arrive (dev only).
  Uint8List? depthPreview;
  Uint8List? segPreview;
  Uint8List? yoloPreview;
  Uint8List? maskPreview;

  /// Number of preview attachments received so far (correlation bookkeeping).
  int receivedAttachments = 0;

  /// Client-measured round trip: frame sent -> JSON received, in ms.
  double? endToEndMs;

  DetectionResult({
    required this.frameId,
    required this.instruction,
    required this.obstacles,
    required this.freeZones,
    required this.freeZonesRaw,
    required this.metrics,
    required this.frameWidth,
    required this.frameHeight,
    required this.skipped,
    required this.highestPriority,
    required this.mad,
    required this.depthAttached,
    required this.segAttached,
    required this.yoloAttached,
    required this.maskAttached,
  });

  /// How many binary preview messages this response will be followed by.
  int get expectedAttachments =>
      (depthAttached ? 1 : 0) +
      (segAttached ? 1 : 0) +
      (yoloAttached ? 1 : 0) +
      (maskAttached ? 1 : 0);

  bool get hasInstruction => instruction.trim().isNotEmpty;

  static bool _labelIsCar(String? label) =>
      label != null && label.toLowerCase().contains('car');

  /// Whether a car is present (as the highest-priority obstacle or in the list).
  bool get hasCar =>
      _labelIsCar(highestPriority?.label) ||
      obstacles.any((o) => _labelIsCar(o.label));

  /// Smallest clearance among BLOCKED free-zone regions (meters), or null.
  double? get minBlockedClearanceM {
    double? m;
    for (final z in freeZones) {
      if (!z.free && z.clearanceM != null) {
        if (m == null || z.clearanceM! < m) m = z.clearanceM;
      }
    }
    return m;
  }

  /// Estimated distance (meters) to the nearest detected car, using:
  ///  1. the car obstacle's own distance, if the server provides one;
  ///  2. else the clearance of the free-zone region the car's bbox centre falls
  ///     in (the car blocks that region);
  ///  3. else the smallest blocked-region clearance.
  /// Returns null when no car / no distance signal is available.
  double? carDistanceMeters() {
    final cars = <DetectedObstacle>[
      if (_labelIsCar(highestPriority?.label)) highestPriority!,
      ...obstacles.where((o) => _labelIsCar(o.label)),
    ];
    if (cars.isEmpty) return null;

    double? best;
    for (final car in cars) {
      double? d = car.distanceMeters;
      if (d == null && car.bbox.length >= 4 && freeZones.isNotEmpty) {
        final centreX = (car.bbox[0] + car.bbox[2]) / 2.0;
        final idx =
            (centreX * freeZones.length).floor().clamp(0, freeZones.length - 1);
        d = freeZones[idx].clearanceM;
      }
      if (d != null && (best == null || d < best)) best = d;
    }
    return best ?? minBlockedClearanceM;
  }

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    final instructionValue = json['instruction'];
    final obstaclesRaw = json['obstacles'];
    final obstacles = obstaclesRaw is List
        ? obstaclesRaw
            .whereType<Map<String, dynamic>>()
            .map(DetectedObstacle.fromJson)
            .toList()
        : <DetectedObstacle>[];

    final hpRaw = json['highest_priority'];
    final highestPriority = hpRaw is Map<String, dynamic>
        ? DetectedObstacle.fromJson(hpRaw)
        : null;

    final metricsRaw = json['metrics'];
    final metrics = metricsRaw is Map<String, dynamic>
        ? ServerMetrics(metricsRaw)
        : ServerMetrics.empty;

    final frameSize = json['frame_size'];
    int? dim(String k) {
      if (frameSize is Map && frameSize[k] is num) {
        return (frameSize[k] as num).toInt();
      }
      return null;
    }

    double? num2(dynamic v) => v is num ? v.toDouble() : null;
    double? metric(String k) =>
        metricsRaw is Map ? num2(metricsRaw[k]) : null;
    // MAD sources, in priority order:
    //  - skipped frames send a FRESH value top-level as `sig_mad` (the response
    //    is a copy of the last processed one, so its metrics.frame_signature_mad
    //    would be stale — top-level wins).
    //  - processed frames report it inside metrics as `frame_signature_mad`.
    final mad = num2(json['sig_mad']) ??
        num2(json['mad']) ??
        num2(json['frame_mad']) ??
        metric('frame_signature_mad') ??
        metric('mad') ??
        metric('frame_mad');

    return DetectionResult(
      frameId: (json['frame_id'] as num?)?.toInt() ?? 0,
      instruction: instructionValue is String ? instructionValue.trim() : '',
      obstacles: obstacles,
      freeZones: parseFreeZones(json['free_zones']),
      freeZonesRaw: json['free_zones'],
      metrics: metrics,
      frameWidth: dim('w'),
      frameHeight: dim('h'),
      skipped: json['skipped'] == true,
      highestPriority: highestPriority,
      mad: mad,
      depthAttached: json['depth_attached'] == true,
      segAttached: json['seg_attached'] == true,
      yoloAttached: json['yolo_attached'] == true,
      maskAttached: json['mask_attached'] == true,
    );
  }
}
