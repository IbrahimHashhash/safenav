import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/obstacle_instruction.dart';

/// Client for the detection server's `/ws/navigation` WebSocket.
///
/// Wire protocol (see server.py):
///   Client -> server (binary frame):
///     [0:4]  uint32 BE frame_id
///     [4]    uint8  flags  (bit 0 = request depth preview; we never set it)
///     [5:]   raw JPEG bytes
///   Server -> client (text): JSON response with many fields; we read only
///     `instruction`. Binary preview messages are only sent when bit 0 of the
///     flags byte is set, so we never receive them and ignore any that arrive.
class NavigationWebSocketDatasource {
  NavigationWebSocketDatasource({required String baseUrl})
      : _wsUrl = _toWsUrl(baseUrl);

  final String _wsUrl;

  WebSocketChannel? _channel;
  StreamController<ObstacleInstruction>? _controller;
  bool _connected = false;

  /// Header size: 4-byte frame id + 1-byte flags.
  static const int _headerSize = 5;

  /// Decoded instruction stream (only non-empty `instruction` values).
  Stream<ObstacleInstruction> get stream {
    _controller ??= StreamController<ObstacleInstruction>.broadcast();
    return _controller!.stream;
  }

  bool get isConnected => _connected;

  /// Opens the WebSocket connection. Returns true once the socket is ready.
  Future<bool> connect() async {
    if (_connected) return true;
    _controller ??= StreamController<ObstacleInstruction>.broadcast();

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      // Throws if the handshake fails (server down, wrong host, etc.).
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

  /// Sends a single camera frame to the server.
  ///
  /// [frameId] is wrapped to 32 bits. [includeDepth] is left false so the
  /// server does not ship preview images back.
  void sendFrame(
    Uint8List jpeg,
    int frameId, {
    bool includeDepth = false,
  }) {
    final channel = _channel;
    if (!_connected || channel == null || jpeg.isEmpty) return;

    final packet = Uint8List(_headerSize + jpeg.length);
    final header = ByteData.view(packet.buffer, 0, _headerSize);
    header.setUint32(0, frameId & 0xFFFFFFFF, Endian.big);
    header.setUint8(4, includeDepth ? 0x01 : 0x00);
    packet.setRange(_headerSize, packet.length, jpeg);

    try {
      channel.sink.add(packet);
    } catch (_) {
      _handleDrop();
    }
  }

  void _onMessage(dynamic message) {
    // Only text frames are JSON responses. Binary messages (depth previews)
    // are never requested, so anything binary is ignored.
    if (message is! String) return;

    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) return;
      // Server error responses have no `instruction`; fromJson yields empty.
      final instruction = ObstacleInstruction.fromJson(decoded);
      if (instruction.isEmpty) return;
      _controller?.add(instruction);
    } catch (_) {
      // Malformed payload — skip it.
    }
  }

  void _handleDrop() {
    _connected = false;
    _channel = null;
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

  /// Converts an http(s) base URL into the ws(s) navigation endpoint, e.g.
  /// `http://192.168.1.109:8000` -> `ws://192.168.1.109:8000/ws/navigation`.
  static String _toWsUrl(String baseUrl) {
    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring('https://'.length)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring('http://'.length)}';
    }
    return '$url/ws/navigation';
  }
}
