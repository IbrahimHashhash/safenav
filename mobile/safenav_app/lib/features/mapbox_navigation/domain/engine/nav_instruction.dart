// The ENTIRE spoken vocabulary for the blind-navigation engine lives here.
//
// Allowed instructions ONLY:
//   a) "continue straight ahead" — includes distance in metres (final leg is
//      phrased toward the destination).
//   b) "turn left" / "turn right" — no distance, spoken at the turn point.
//   c) orientation corrections — "turn left/right/around to face the path".
//   d) arrival.
//
// Deliberately NO "slight"/"sharp" turns and NO distance-based pre-announce.
// Ported from the Google-nav engine.

import 'route_path.dart' show TurnDirection;

enum NavInstructionKind { continueStraight, turn, orientation, arrival }

/// A single spoken instruction emitted by the engine.
class NavInstruction {
  final NavInstructionKind kind;
  final String text;

  /// Critical instructions (turns, arrival) bypass the speech cooldown.
  final bool isCritical;

  const NavInstruction._(this.kind, this.text, this.isCritical);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NavInstruction && other.kind == kind && other.text == text);

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => text;
}

/// Builds the (small, fixed) set of allowed instructions.
class NavPhrasing {
  NavPhrasing._();

  static NavInstruction continueStraight(
    double metersRemaining, {
    bool isFinalLeg = false,
  }) {
    final m = _roundMeters(metersRemaining);
    final unit = m == 1 ? 'meter' : 'meters';
    final text = isFinalLeg
        ? 'Continue straight ahead for $m $unit to your destination.'
        : 'Continue straight ahead for $m $unit.';
    return NavInstruction._(NavInstructionKind.continueStraight, text, false);
  }

  static NavInstruction turn(TurnDirection direction) {
    final side = direction == TurnDirection.right ? 'right' : 'left';
    return NavInstruction._(NavInstructionKind.turn, 'Turn $side.', true);
  }

  static NavInstruction orientation(FacingCorrection correction) {
    final String text;
    switch (correction) {
      case FacingCorrection.turnLeft:
        text = 'Turn left to face the path.';
        break;
      case FacingCorrection.turnRight:
        text = 'Turn right to face the path.';
        break;
      case FacingCorrection.turnAround:
        text = 'Turn around to face the path.';
        break;
    }
    return NavInstruction._(NavInstructionKind.orientation, text, false);
  }

  static NavInstruction arrival() => const NavInstruction._(
        NavInstructionKind.arrival,
        'You have arrived at your destination.',
        true,
      );

  static int _roundMeters(double meters) {
    if (meters.isNaN || meters < 0) return 0;
    final r = meters.round();
    return r < 1 ? 1 : r;
  }
}

/// Which way the user must rotate to face the route again.
enum FacingCorrection { turnLeft, turnRight, turnAround }
