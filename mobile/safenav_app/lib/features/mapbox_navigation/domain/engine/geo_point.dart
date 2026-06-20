// Pure value type for a geographic coordinate.
//
// Lives in the domain layer and intentionally does NOT depend on any
// Flutter/SDK type, so the navigation logic stays unit-testable without a
// Flutter binding. Ported from the Google-nav reference engine.

class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GeoPoint &&
          other.latitude == latitude &&
          other.longitude == longitude);

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'GeoPoint(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)})';
}
