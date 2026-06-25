import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/detection_result.dart';

/// Client for the detection server's `/ws/navigation` WebSocket.
///
/// Wire protocol (see server.py):
///   Client -> server (binary frame):
///     [0:4]  uint32 BE frame_id
///     [4]    uint8  flags  (bit 0 = request previews; bit 1 = high quality)
///     [5:]   raw JPEG bytes
///   Server -> client (text): JSON response. We parse the full result.
///   Server -> client (binary, only if previews were requested): one message
///     per preview, [0:4] frame_id, [4] flag (0x01 depth, 0x02 seg, 0x04 yolo,
///     0x08 mask), [5:] image bytes. Correlated back to the JSON via frame_id.
class NavigationWebSocketDatasource {
  NavigationWebSocketDatasource({required String baseUrl})
      : _wsUrl = _toWsUrl(baseUrl);

  final String _wsUrl;

  WebSocketChannel? _channel;
  StreamController<DetectionResult>? _controller;
  bool _connected = false;

  static const int _headerSize = 5;
  static const int _depthFlag = 0x01;
  static const int _segFlag = 0x02;
  static const int _yoloFlag = 0x04;
  static const int _maskFlag = 0x08;

  /// Request-direction flag (header byte 4): ask the server for HIGH-QUALITY
  /// preview JPEGs. Independent of the response-direction preview flags above.
  static const int _reqHqFlag = 0x02;

  /// Results awaiting their preview attachments, keyed by frame_id.
  final Map<int, DetectionResult> _pending = {};

  /// Send timestamps for end-to-end latency, keyed by frame_id.
  final Map<int, DateTime> _sentAt = {};

  /// Rich result stream (one event per fully-assembled frame response).
  Stream<DetectionResult> get stream {
    _controller ??= StreamController<DetectionResult>.broadcast();
    return _controller!.stream;
  }

  bool get isConnected => _connected;

  /// The resolved WebSocket URL (for diagnostics/messages).
  String get url => _wsUrl;

  Future<bool> connect() async {
    if (_connected) return true;
    _controller ??= StreamController<DetectionResult>.broadcast();

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await channel.ready;

      _channel = channel;
      _connected = true;

      channel.stream.listen(
        _onMessage,
        onError: (Object _) => _handleDrop(),
        onDone: _handleDrop,
        cancelOnError: false,
      );
      return true;
    } catch (_) {
      _handleDrop();
      return false;
    }
  }

  /// Sends one camera frame. Set [includePreviews] to receive the model
  /// preview images back (used by the developer screen). Set [highQuality] to
  /// ask the server for full-resolution preview JPEGs — large (~0.5–3.6 MB
  /// each), so only for on-demand single-frame captures over a good LAN.
  void sendFrame(
    Uint8List jpeg,
    int frameId, {
    bool includePreviews = false,
    bool highQuality = false,
  }) {
    final channel = _channel;
    if (!_connected || channel == null || jpeg.isEmpty) return;

    final packet = Uint8List(_headerSize + jpeg.length);
    final header = ByteData.view(packet.buffer, 0, _headerSize);
    header.setUint32(0, frameId & 0xFFFFFFFF, Endian.big);
    var flags = includePreviews ? _depthFlag : 0x00;
    if (highQuality) flags |= _reqHqFlag;
    header.setUint8(4, flags);
    packet.setRange(_headerSize, packet.length, jpeg);

    _sentAt[frameId] = DateTime.now();
    // Bound memory if responses are lost.
    if (_sentAt.length > 120) {
      final cutoff = frameId - 60;
      _sentAt.removeWhere((id, _) => id < cutoff);
    }

    try {
      channel.sink.add(packet);
    } catch (_) {
      _handleDrop();
    }
  }

  void _onMessage(dynamic message) {
    if (message is String) {
      _onJson(message);
    } else if (message is List<int>) {
      _onBinary(message);
    }
  }

  void _onJson(String text) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      json = decoded;
    } catch (_) {
      return; // malformed / server error text
    }

    final result = DetectionResult.fromJson(json);

    final sent = _sentAt.remove(result.frameId);
    if (sent != null) {
      result.endToEndMs =
          DateTime.now().difference(sent).inMicroseconds / 1000.0;
    }

    // A new JSON means any older pending frame's previews are not coming.
    _flushOlderThan(result.frameId);

    if (result.expectedAttachments == 0) {
      _emit(result);
    } else {
      _pending[result.frameId] = result;
    }
  }

  void _onBinary(List<int> bytes) {
    if (bytes.length < _headerSize) return;
    final frameId =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    final flag = bytes[4];

    final result = _pending[frameId];
    if (result == null) return;

    final payload = Uint8List.fromList(bytes.sublist(_headerSize));
    switch (flag) {
      case _depthFlag:
        result.depthPreview = payload;
        break;
      case _segFlag:
        result.segPreview = payload;
        break;
      case _yoloFlag:
        result.yoloPreview = payload;
        break;
      case _maskFlag:
        result.maskPreview = payload;
        break;
      default:
        return;
    }

    result.receivedAttachments++;
    if (result.receivedAttachments >= result.expectedAttachments) {
      _pending.remove(frameId);
      _emit(result);
    }
  }

  /// Emit (and stop waiting for) any pending results older than [frameId].
  void _flushOlderThan(int frameId) {
    if (_pending.isEmpty) return;
    final stale = _pending.keys.where((id) => id < frameId).toList();
    for (final id in stale) {
      final r = _pending.remove(id);
      if (r != null) _emit(r);
    }
  }

  void _emit(DetectionResult result) => _controller?.add(result);

  void _handleDrop() {
    _connected = false;
    _channel = null;
    _pending.clear();
    _sentAt.clear();
  }

  Future<void> disconnect() async {
    final channel = _channel;
    _handleDrop();
    await channel?.sink.close();
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller?.close();
    _controller = null;
  }

  /// Builds the navigation WebSocket URL from the configured base URL,
  /// tolerating whatever form `OBSTACLE_API_URL` is given in:
  ///   `http://host:8000`            -> `ws://host:8000/ws/navigation`
  ///   `https://host`                -> `wss://host/ws/navigation`
  ///   `ws://host:8000`              -> `ws://host:8000/ws/navigation`
  ///   `ws://host:8000/ws/navigation`-> unchanged (path not duplicated)
  static String _toWsUrl(String baseUrl) {
    var url = baseUrl.trim();

    // Normalise scheme to ws/wss (leave ws/wss as-is).
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring('https://'.length)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring('http://'.length)}';
    }

    // Drop any trailing slash(es).
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    // Append the endpoint path only if it is not already there.
    const path = '/ws/navigation';
    if (!url.endsWith(path)) {
      url = '$url$path';
    }
    return url;
  }
}
