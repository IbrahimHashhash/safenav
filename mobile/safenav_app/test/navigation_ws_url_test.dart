import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/obstacle_avoidance/data/datasources/navigation_ws_datasource.dart';

void main() {
  group('NavigationWebSocketDatasource url', () {
    String urlFor(String base) =>
        NavigationWebSocketDatasource(baseUrl: base).url;

    test('appends the path to a bare http host', () {
      expect(urlFor('http://192.168.1.109:8000'),
          'ws://192.168.1.109:8000/ws/navigation');
    });

    test('converts https to wss', () {
      expect(urlFor('https://example.com'), 'wss://example.com/ws/navigation');
    });

    test('does NOT duplicate the path when already present', () {
      expect(urlFor('ws://176.119.254.184:8000/ws/navigation'),
          'ws://176.119.254.184:8000/ws/navigation');
    });

    test('handles http with the path already included', () {
      expect(urlFor('http://host:8000/ws/navigation'),
          'ws://host:8000/ws/navigation');
    });

    test('trims a trailing slash', () {
      expect(urlFor('http://host:8000/'), 'ws://host:8000/ws/navigation');
    });
  });
}
