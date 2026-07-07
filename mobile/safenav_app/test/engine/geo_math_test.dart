import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/geo_math.dart';
import 'package:safenav_app/features/mapbox_navigation/domain/engine/geo_point.dart';

void main() {
  group('angle helpers', () {
    test('normalizeDegrees wraps into [0,360)', () {
      expect(GeoMath.normalizeDegrees(370), closeTo(10, 1e-9));
      expect(GeoMath.normalizeDegrees(-10), closeTo(350, 1e-9));
      expect(GeoMath.normalizeDegrees(0), closeTo(0, 1e-9));
      expect(GeoMath.normalizeDegrees(360), closeTo(0, 1e-9));
    });

    test('signedAngularDifference handles wrap and sign', () {
      expect(GeoMath.signedAngularDifference(0, 90), closeTo(90, 1e-9));
      expect(GeoMath.signedAngularDifference(0, 270), closeTo(-90, 1e-9));
      expect(GeoMath.signedAngularDifference(350, 10), closeTo(20, 1e-9));
      expect(GeoMath.signedAngularDifference(10, 350), closeTo(-20, 1e-9));
    });

    test('angularDistance is symmetric and in [0,180]', () {
      expect(GeoMath.angularDistance(350, 10), closeTo(20, 1e-9));
      expect(GeoMath.angularDistance(10, 350), closeTo(20, 1e-9));
      expect(GeoMath.angularDistance(0, 180), closeTo(180, 1e-9));
    });

    test('circularMeanDegrees averages across wrap', () {
      expect(GeoMath.circularMeanDegrees([]), isNull);
      final mean = GeoMath.circularMeanDegrees([350, 10])!;
      expect(GeoMath.angularDistance(mean, 0), lessThan(1e-6));
    });
  });

  group('distance & bearing', () {
    const a = GeoPoint(31.9600, 35.1800);
    const east = GeoPoint(31.9600, 35.1820);
    const north = GeoPoint(31.9620, 35.1800);

    test('distance is positive and symmetric', () {
      final d = GeoMath.distanceMeters(a, east);
      expect(d, greaterThan(150));
      expect(d, lessThan(250));
      expect(GeoMath.distanceMeters(east, a), closeTo(d, 1e-6));
    });

    test('bearing east ~ 90, north ~ 0', () {
      expect(GeoMath.angularDistance(GeoMath.bearing(a, east), 90),
          lessThan(1.0));
      expect(GeoMath.angularDistance(GeoMath.bearing(a, north), 0),
          lessThan(1.0));
    });
  });

  group('projectOntoPolyline', () {
    const a = GeoPoint(31.9600, 35.1800);
    const b = GeoPoint(31.9600, 35.1820);
    const c = GeoPoint(31.9620, 35.1820);
    final verts = [a, b, c];
    late List<double> cum;

    setUp(() => cum = GeoMath.cumulativeDistances(verts));

    test('cumulative distances are monotonic from 0', () {
      expect(cum.first, 0);
      expect(cum[1], greaterThan(0));
      expect(cum[2], greaterThan(cum[1]));
    });

    test('point on first segment projects with ~0 cross-track', () {
      const mid = GeoPoint(31.9600, 35.1810);
      final p = GeoMath.projectOntoPolyline(mid, verts, cum);
      expect(p.segmentIndex, 0);
      expect(p.crossTrackDistance, lessThan(1.0));
      expect(p.t, closeTo(0.5, 0.05));
      expect(p.distanceAlong, closeTo(cum[1] * 0.5, 2.0));
    });

    test('off-path point keeps cross-track distance', () {
      const off = GeoPoint(31.9601, 35.1810);
      final p = GeoMath.projectOntoPolyline(off, verts, cum);
      expect(p.segmentIndex, 0);
      expect(p.crossTrackDistance, greaterThan(8));
      expect(p.crossTrackDistance, lessThan(15));
    });

    test('point near second segment projects onto it', () {
      const mid2 = GeoPoint(31.9610, 35.1820);
      final p = GeoMath.projectOntoPolyline(mid2, verts, cum);
      expect(p.segmentIndex, 1);
      expect(p.distanceAlong, greaterThan(cum[1]));
    });
  });
}
