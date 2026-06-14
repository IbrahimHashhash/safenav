import 'dart:async';

import 'package:flutter_compass/flutter_compass.dart';

import 'compass_service.dart';

class FlutterCompassService implements CompassService {
  StreamController<double?>? _controller;
  StreamSubscription<CompassEvent>? _sub;
  double? _current;

  @override
  double? get currentHeading => _current;

  @override
  Stream<double?> get headingStream {
    _controller ??= StreamController<double?>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return _controller!.stream;
  }

  void _start() {
    final stream = FlutterCompass.events;
    if (stream == null) {
      _current = null;
      _controller?.add(null);
      return;
    }

    _sub = stream.listen(
      (event) {
        final h = event.heading;
        if (h == null) {
          _current = null;
        } else {
          double normalized = h % 360;
          if (normalized < 0) normalized += 360;
          _current = normalized;
        }
        _controller?.add(_current);
      },
      onError: (Object _) {
        _current = null;
        _controller?.add(null);
      },
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller?.close();
    _controller = null;
  }
}
