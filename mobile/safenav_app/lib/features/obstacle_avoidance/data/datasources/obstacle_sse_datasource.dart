import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/obstacle_instruction.dart';



class ObstacleSseDatasource {
  final String baseUrl;

  ObstacleSseDatasource({required this.baseUrl});

  
  http.Client? _client;
  StreamSubscription<String>? _lineSubscription;
  StreamController<ObstacleInstruction>? _controller;

  
  Stream<ObstacleInstruction> get stream {
    _controller ??= StreamController<ObstacleInstruction>.broadcast();
    return _controller!.stream;
  }

  
  
  Future<void> connect() async {
    if (_client != null) return;

    _controller ??= StreamController<ObstacleInstruction>.broadcast();
    _client = http.Client();

    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/obstacle-stream'),
      );
      
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        print('[ObstacleSse] unexpected status: ${response.statusCode}');
        disconnect();
        return;
      }

      _lineSubscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _handleLine,
            onError: (Object error) {
              print('[ObstacleSse] stream error: $error');
              disconnect();
            },
            onDone: () {
              print('[ObstacleSse] stream closed by server');
              disconnect();
            },
            cancelOnError: false,
          );
    } catch (e) {
      print('[ObstacleSse] connect error: $e');
      disconnect();
    }
  }

  void _handleLine(String line) {
    
    if (!line.startsWith('data: ')) return;

    final jsonStr = line.substring(6).trim();
    if (jsonStr.isEmpty) return;

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final instruction = ObstacleInstruction.fromJson(map);
      print('[ObstacleSse] received: $instruction');
      _controller?.add(instruction);
    } catch (e) {
      print('[ObstacleSse] parse error on "$jsonStr": $e');
    }
  }

  
  void disconnect() {
    _lineSubscription?.cancel();
    _lineSubscription = null;
    _client?.close();
    _client = null;
    
  }

  void dispose() {
    disconnect();
    _controller?.close();
    _controller = null;
  }
}