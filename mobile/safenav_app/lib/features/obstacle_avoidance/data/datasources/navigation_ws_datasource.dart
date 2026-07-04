import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../domain/entities/detection_result.dart';












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

  
  final Map<int, DetectionResult> _pending = {};

  
  final Map<int, DateTime> _sentAt = {};

  
  Stream<DetectionResult> get stream {
    _controller ??= StreamController<DetectionResult>.broadcast();
    return _controller!.stream;
  }

  bool get isConnected => _connected;

  
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

  
  
  void sendFrame(
    Uint8List jpeg,
    int frameId, {
    bool includePreviews = false,
  }) {
    final channel = _channel;
    if (!_connected || channel == null || jpeg.isEmpty) return;

    final packet = Uint8List(_headerSize + jpeg.length);
    final header = ByteData.view(packet.buffer, 0, _headerSize);
    header.setUint32(0, frameId & 0xFFFFFFFF, Endian.big);
    header.setUint8(4, includePreviews ? _depthFlag : 0x00);
    packet.setRange(_headerSize, packet.length, jpeg);

    _sentAt[frameId] = DateTime.now();
    
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
      return; 
    }

    final result = DetectionResult.fromJson(json);

    final sent = _sentAt.remove(result.frameId);
    if (sent != null) {
      result.endToEndMs =
          DateTime.now().difference(sent).inMicroseconds / 1000.0;
    }

    
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

  
  
  
  
  
  
  static String _toWsUrl(String baseUrl) {
    var url = baseUrl.trim();

    
    if (url.startsWith('https://')) {
      url = 'wss://${url.substring('https://'.length)}';
    } else if (url.startsWith('http://')) {
      url = 'ws://${url.substring('http://'.length)}';
    }

    
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    
    const path = '/ws/navigation';
    if (!url.endsWith(path)) {
      url = '$url$path';
    }
    return url;
  }
}
