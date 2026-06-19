import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/widgets/caption_card.dart';
import '../../../shared/widgets/streaming_button.dart';
import '../../mapbox_navigation/presentation/widgets/navigation_map_view.dart';
import '../../obstacle_avoidance/application/obstacle_listener_service.dart';
import '../../obstacle_avoidance/domain/entities/detection_result.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_cubit.dart';
import '../../voice_interaction/presentation/cubit/voice_assistant_state.dart';

enum _ModelPreview { yolo, sam, depth }

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
  _ModelPreview _selected = _ModelPreview.yolo;
  String _lastSpoken = '';

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
          child: StreamBuilder<DetectionResult>(
            stream: widget.listener.results,
            initialData: widget.listener.lastResult,
            builder: (context, snapshot) {
              final result = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StreamingButton(
                    streaming: widget.streaming,
                    busy: widget.busy,
                    onPressed: widget.onToggleStreaming,
                  ),
                  const SizedBox(height: 16),

                  _sectionTitle('Camera preview'),
                  _cameraPreview(context),
                  const SizedBox(height: 16),

                  _sectionTitle('Map & current location'),
                  _mapAndCoords(),
                  const SizedBox(height: 16),

                  _sectionTitle('Spoken instruction (navigation / obstacle)'),
                  CaptionCard(
                    label: 'Last spoken',
                    text: _lastSpoken,
                    icon: Icons.record_voice_over,
                    accent: const Color(0xFF26C6DA),
                  ),
                  const SizedBox(height: 16),

                  _sectionTitle('Model previews'),
                  _previewSelector(),
                  const SizedBox(height: 8),
                  _previewImage(result),
                  const SizedBox(height: 16),

                  _sectionTitle('Detected obstacles'),
                  _obstacleList(result),
                  const SizedBox(height: 16),

                  _sectionTitle('Metrics'),
                  _metrics(result),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      );

  // Camera preview occupies half the screen height; cover-fit so it is never
  // squeezed.
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
                  // previewSize is in sensor (landscape) orientation; swap for
                  // the portrait widget so cover-fit keeps the aspect ratio.
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

  Widget _mapAndCoords() {
    return SizedBox(
      height: 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: const NavigationMapView(showCoordinates: true),
      ),
    );
  }

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

  String _previewLabel(_ModelPreview p) {
    switch (p) {
      case _ModelPreview.yolo:
        return 'YOLO boxes';
      case _ModelPreview.sam:
        return 'Ground (SAM 2.1)';
      case _ModelPreview.depth:
        return 'Depth';
    }
  }

  Uint8List? _selectedBytes(DetectionResult? r) {
    if (r == null) return null;
    switch (_selected) {
      case _ModelPreview.yolo:
        return r.yoloPreview;
      case _ModelPreview.sam:
        return r.segPreview;
      case _ModelPreview.depth:
        return r.depthPreview;
    }
  }

  Widget _previewImage(DetectionResult? r) {
    final bytes = _selectedBytes(r);
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: bytes != null
          ? Image.memory(
              bytes,
              gaplessPlayback: true,
              fit: BoxFit.contain,
            )
          : Text(
              widget.streaming
                  ? 'Waiting for ${_previewLabel(_selected)} preview…'
                  : 'Start streaming to receive previews',
              style: const TextStyle(color: Colors.white70),
            ),
    );
  }

  Widget _obstacleList(DetectionResult? r) {
    final obstacles = r?.obstacles ?? const <DetectedObstacle>[];
    if (obstacles.isEmpty) {
      return const Text('No obstacles detected.',
          style: TextStyle(color: Colors.white54));
    }
    return Column(
      children: [
        for (final o in obstacles)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                const Icon(Icons.crop_square, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Text(o.label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${(o.confidence * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    o.distanceMeters != null
                        ? '${o.distanceMeters!.toStringAsFixed(1)} m'
                        : '— m',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.cyanAccent),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _metrics(DetectionResult? r) {
    if (r == null) {
      return const Text('No metrics yet.',
          style: TextStyle(color: Colors.white54));
    }
    final rows = <Widget>[
      _metricRow(
        'End-to-end latency (client)',
        r.endToEndMs != null
            ? '${r.endToEndMs!.toStringAsFixed(1)} ms'
            : '—',
        highlight: true,
      ),
      if (r.skipped)
        _metricRow('Frame', 'skipped (reused previous result)'),
    ];

    // All scalar metrics reported by the server.
    for (final e in r.metrics.scalarEntries) {
      final isMs = e.key.endsWith('_ms');
      final value = e.value;
      final text = isMs
          ? '${value.toStringAsFixed(1)} ms'
          : value is int
              ? value.toString()
              : value.toStringAsFixed(2);
      rows.add(_metricRow(_prettyKey(e.key), text));
    }

    return Column(children: rows);
  }

  String _prettyKey(String key) {
    final cleaned = key.replaceAll('_ms', '').replaceAll('_', ' ');
    return cleaned.isEmpty
        ? key
        : '${cleaned[0].toUpperCase()}${cleaned.substring(1)}';
  }

  Widget _metricRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: highlight ? Colors.amberAccent : Colors.white70,
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: highlight ? Colors.amberAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
