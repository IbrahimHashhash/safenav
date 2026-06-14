abstract class CompassService {
  Stream<double?> get headingStream;

  double? get currentHeading;

  Future<void> dispose();
}
