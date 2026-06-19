import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/widgets/caption_card.dart';
import '../../../shared/widgets/streaming_button.dart';
import '../../mapbox_navigation/presentation/widgets/navigation_map_view.dart';
import '../../obstacle_avoidance/application/obstacle_listener_service.dart';
import '../../obstacle_avoidance/domain/entities/detection_result.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_state.dart';

enum _ModelPreview { yolo, depth, freeZone }

/// Developer/debug screen: live camera preview, the navigation map with the
/// current coordinates, a caption of the last spoken instruction (navigation
/// or obstacle), per-model preview images from the server, the detected
/// obstacle list, and all server metrics plus client end-to-end latency.
class DeveloperScreen extends StatefulWidget {
  const DeveloperScreen({
    super.key,
    required this.listener,
    required this.streaming,
    required this.busy,
    required this.onToggleStreaming,
  });

  final ObstacleListenerService listener;
  final bool streaming;
  final bool busy;
  final VoidCallback onToggleStreaming;

  @override
  State<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends State<DeveloperScreen> {
  static const Color _accent = Color(0xFF26C6DA);

  _ModelPreview _selected = _ModelPreview.yolo;
  String _lastSpoken = '';

  StreamSubscription<DetectionResult>? _sub;
  StreamSubscription<String>? _captureSub;
  DetectionResult? _result;
  bool _capturing = false;
  String? _capturesDir;

  // Last successfully received preview per model. Kept across skipped frames
  // (a skipped frame carries no previews) so the image never blanks out.
  Uint8List? _lastYolo;
  Uint8List? _lastDepth;

  @override
  void initState() {
    super.initState();
    _result = widget.listener.lastResult;
    _cachePreviews(_result);
    _sub = widget.listener.results.listen((r) {
      if (!mounted) return;
      setState(() {
        _result = r;
        _cachePreviews(r);
      });
    });
    _captureSub = widget.listener.captureEvents.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
    });
    widget.listener.captureLog.directoryPath().then((path) {
      if (mounted) setState(() => _capturesDir = path);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _captureSub?.cancel();
    super.dispose();
  }

  Future<void> _exportCsv() async {
    final log = widget.listener.captureLog;
    final exists = await log.csvExists();
    if (!mounted) return;
    if (!exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No captures to export yet.')),
      );
      return;
    }
    final path = await log.csvPath();
    await Share.shareXFiles([XFile(path)], text: 'SafeNav capture log');
  }

  Future<void> _onCapture() async {
    setState(() => _capturing = true);
    final error = await widget.listener.captureOnce();
    if (!mounted) return;
    setState(() => _capturing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'Capturing frame… it will be saved when the response arrives.',
        ),
      ),
    );
  }

  void _cachePreviews(DetectionResult? r) {
    if (r == null) return;
    if (r.yoloPreview != null) _lastYolo = r.yoloPreview;
    if (r.depthPreview != null) _lastDepth = r.depthPreview;
  }

  Uint8List? get _selectedBytes => switch (_selected) {
        _ModelPreview.yolo => _lastYolo,
        _ModelPreview.depth => _lastDepth,
        _ModelPreview.freeZone => null,
      };

  @override
  Widget build(BuildContext context) {
    return BlocListener<VoiceAssistantCubit, VoiceAssistantState>(
      listener: (context, state) {
        if (state is VoiceSpeaking && state.text.isNotEmpty) {
          setState(() => _lastSpoken = state.text);
        }
      },
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: StreamingButton(
                      streaming: widget.streaming,
                      busy: widget.busy,
                      onPressed: widget.onToggleStreaming,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _capturing ? null : _onCapture,
                      icon: _capturing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.camera_alt),
                      label: const Text('Capture frame'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF5C6BC0),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _capturesDir != null
                          ? 'Captures: $_capturesDir'
                          : 'Captures are saved on this device',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _exportCsv,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Export CSV'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _statusStrip(),
              const SizedBox(height: 16),

              _section(
                icon: Icons.videocam,
                title: 'Camera preview',
                child: _cameraPreview(context),
              ),
              const SizedBox(height: 14),

              _section(
                icon: Icons.record_voice_over,
                title: 'Spoken instruction (navigation / obstacle)',
                child: CaptionCard(
                  label: 'Last spoken',
                  text: _lastSpoken,
                  icon: Icons.record_voice_over,
                  accent: _accent,
                ),
              ),
              const SizedBox(height: 14),

              _section(
                icon: Icons.map,
                title: 'Map & current location',
                child: SizedBox(
                  height: 240,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: const NavigationMapView(showCoordinates: true),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              _section(
                icon: Icons.image_search,
                title: 'Model previews',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _previewSelector(),
                    const SizedBox(height: 10),
                    _previewImage(),
                    if (_selected == _ModelPreview.freeZone)
                      _clearanceCards(),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              _section(
                icon: Icons.report,
                title: 'Detected obstacles',
                child: _obstacleList(),
              ),
              const SizedBox(height: 14),

              _section(
                icon: Icons.speed,
                title: 'Performance metrics',
                child: _metrics(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Layout helpers -------------------------------------------------------

  Widget _section({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  // --- Status strip (frame id, skipped, MAD, latency, fps) ------------------

  Widget _statusStrip() {
    final r = _result;
    final skipped = r?.skipped == true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _statTile(
              tileWidth,
              'Frame sent',
              r != null ? '#${r.frameId}' : '—',
              icon: Icons.tag,
            ),
            _statTile(
              tileWidth,
              'Frame status',
              r == null ? '—' : (skipped ? 'Skipped' : 'Processed'),
              valueColor: r == null
                  ? Colors.white
                  : (skipped ? Colors.orangeAccent : Colors.lightGreenAccent),
              icon: skipped ? Icons.fast_forward : Icons.check_circle,
            ),
            _statTile(
              tileWidth,
              'MAD',
              r?.mad != null ? r!.mad!.toStringAsFixed(2) : '—',
              icon: Icons.compare,
            ),
            _statTile(
              tileWidth,
              'End-to-end',
              r?.endToEndMs != null
                  ? '${r!.endToEndMs!.toStringAsFixed(0)} ms'
                  : '—',
              valueColor: Colors.amberAccent,
              icon: Icons.timer,
            ),
            _statTile(
              tileWidth,
              'Server FPS',
              r?.metrics.serverFps != null
                  ? r!.metrics.serverFps!.toStringAsFixed(1)
                  : '—',
              icon: Icons.bolt,
            ),
            _statTile(
              tileWidth,
              'Server total',
              r?.metrics.totalMs != null
                  ? '${r!.metrics.totalMs!.toStringAsFixed(0)} ms'
                  : '—',
              icon: Icons.dns,
            ),
          ],
        );
      },
    );
  }

  Widget _statTile(
    double width,
    String label,
    String value, {
    Color valueColor = Colors.white,
    IconData? icon,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
              ],
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // --- Camera preview (half screen, cover-fit) ------------------------------

  Widget _cameraPreview(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.5;
    final cam = widget.listener.cameraSource;
    final ready = cam.isReady && cam.previewSize != null;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ready
            ? FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: cam.previewSize!.height,
                  height: cam.previewSize!.width,
                  child: cam.buildPreview(),
                ),
              )
            : Container(
                color: Colors.white10,
                alignment: Alignment.center,
                child: Text(
                  widget.streaming
                      ? 'Starting camera…'
                      : 'Start streaming to see the camera preview',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
      ),
    );
  }

  // --- Model previews -------------------------------------------------------

  Widget _previewSelector() {
    return Wrap(
      spacing: 8,
      children: [
        for (final p in _ModelPreview.values)
          ChoiceChip(
            label: Text(_previewLabel(p)),
            selected: _selected == p,
            onSelected: (_) => setState(() => _selected = p),
          ),
      ],
    );
  }

  String _previewLabel(_ModelPreview p) => switch (p) {
        _ModelPreview.yolo => 'YOLO boxes',
        _ModelPreview.depth => 'Depth',
        _ModelPreview.freeZone => 'Free zones',
      };

  Widget _previewImage() {
    if (_selected == _ModelPreview.freeZone) {
      return _freeZoneView();
    }

    final bytes = _selectedBytes;
    final skipped = _result?.skipped == true;

    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bytes != null)
            Image.memory(bytes, gaplessPlayback: true, fit: BoxFit.contain)
          else if (widget.streaming)
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            )
          else
            const Center(
              child: Text(
                'Start streaming to receive previews',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          // When the current frame was skipped, keep showing the last preview
          // but make clear it is not live.
          if (skipped && bytes != null)
            Positioned(
              left: 8,
              top: 8,
              child: _badge('Skipped · last processed frame',
                  Colors.orangeAccent),
            ),
        ],
      ),
    );
  }

  /// Visualises the server's free-zone analysis: the vertical regions across
  /// the analysis band, green = free, red = blocked.
  Widget _freeZoneView() {
    final zones = _result?.freeZones ?? const <FreeZone>[];
    final skipped = _result?.skipped == true;

    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: zones.isEmpty
          ? const Center(
              child: Text(
                'No free-zone data yet. Capture a frame or start streaming.',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            )
          : Stack(
              children: [
                // The analysis band with the vertical regions.
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      height: 120,
                      child: Row(
                        children: [
                          for (var i = 0; i < zones.length; i++)
                            Expanded(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 3),
                                decoration: BoxDecoration(
                                  color: zones[i].free
                                      ? Colors.green.withValues(alpha: 0.65)
                                      : Colors.red.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.white.withValues(
                                          alpha: 0.85),
                                      width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${i + 1}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      zones[i].free ? 'free' : 'blocked',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: _badge(
                    'Free-zone analysis · ${zones.length} regions',
                    _accent,
                  ),
                ),
                if (skipped)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: _badge('Skipped · last frame', Colors.orangeAccent),
                  ),
              ],
            ),
    );
  }

  /// Per-region clearance cards shown below the free-zone band. Green when the
  /// region is clear/free, red when blocked.
  Widget _clearanceCards() {
    final zones = _result?.freeZones ?? const <FreeZone>[];
    if (zones.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          for (var i = 0; i < zones.length; i++)
            Expanded(child: _clearanceCard(i, zones[i])),
        ],
      ),
    );
  }

  Widget _clearanceCard(int index, FreeZone zone) {
    final color = zone.free ? Colors.green : Colors.red;
    final clearance =
        zone.clearanceM != null ? '${zone.clearanceM!.toStringAsFixed(1)} m' : '—';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Column(
        children: [
          Text(
            'R${index + 1}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            clearance,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            zone.free ? 'clear' : 'blocked',
            style: TextStyle(color: color, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(
        text,
        style: TextStyle(
            color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  // --- Obstacles ------------------------------------------------------------

  Widget _obstacleList() {
    final obstacles = _result?.obstacles ?? const <DetectedObstacle>[];
    if (obstacles.isEmpty) {
      return const Text('No obstacles detected.',
          style: TextStyle(color: Colors.white54));
    }
    return Column(
      children: [
        for (final o in obstacles)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.crop_square, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(o.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${(o.confidence * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    o.distanceMeters != null
                        ? '${o.distanceMeters!.toStringAsFixed(1)} m'
                        : '— m',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.cyanAccent, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // --- Metrics --------------------------------------------------------------

  Widget _metrics() {
    final r = _result;
    if (r == null) {
      return const Text('No metrics yet.',
          style: TextStyle(color: Colors.white54));
    }
    final rows = <Widget>[
      _metricRow(
        'End-to-end latency (client)',
        r.endToEndMs != null ? '${r.endToEndMs!.toStringAsFixed(1)} ms' : '—',
        highlight: true,
      ),
      if (r.mad != null) _metricRow('MAD', r.mad!.toStringAsFixed(2)),
      _metricRow('Frame', r.skipped ? 'skipped (reused last result)' : 'processed'),
    ];

    for (final e in r.metrics.scalarEntries) {
      // Shown separately as the MAD tile/row; don't duplicate it here.
      if (e.key == 'mad' ||
          e.key == 'frame_mad' ||
          e.key == 'frame_signature_mad') {
        continue;
      }
      final isMs = e.key.endsWith('_ms');
      final value = e.value;
      final text = isMs
          ? '${value.toStringAsFixed(1)} ms'
          : value is int
              ? value.toString()
              : value.toStringAsFixed(2);
      rows.add(_metricRow(_prettyKey(e.key), text));
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.10)),
          rows[i],
        ],
      ],
    );
  }

  String _prettyKey(String key) {
    final cleaned = key.replaceAll('_ms', '').replaceAll('_', ' ');
    return cleaned.isEmpty
        ? key
        : '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
  }

  Widget _metricRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: highlight ? Colors.amberAccent : Colors.white70,
                fontSize: 15,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: highlight ? Colors.amberAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
