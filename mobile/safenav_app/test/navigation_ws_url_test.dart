import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/obstacle_avoidance/data/datasources/navigation_ws_datasource.dart';

void main() {
  group('NavigationWebSocketDatasource url', () {
    String urlFor(String base) =>
        NavigationWebSocketDatasource(baseUrl: base).url;

    test('converts http to ws and keeps the URL as-is otherwise', () {
      expect(urlFor('http://192.168.1.109:8000/ws/navigation'),
          'ws://192.168.1.109:8000/ws/navigation');
    });

    test('converts https to wss', () {
      expect(urlFor('https://example.com/ws/navigation'),
          'wss://example.com/ws/navigation');
    });

    test('leaves a ws:// URL unchanged', () {
      expect(urlFor('ws://176.119.254.184:8000/ws/navigation'),
          'ws://176.119.254.184:8000/ws/navigation');
    });

    test('does NOT append a path (URL is used as given)', () {
      expect(urlFor('http://host:8000'), 'ws://host:8000');
    });
  });
}
