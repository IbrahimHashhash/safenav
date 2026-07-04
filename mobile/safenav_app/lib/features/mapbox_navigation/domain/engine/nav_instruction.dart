











import 'route_path.dart' show TurnDirection;

enum NavInstructionKind { continueStraight, turn, orientation, arrival }


class NavInstruction {
  final NavInstructionKind kind;
  final String text;

  
  final bool isCritical;

  
  
  
  
  
  
  final double? distanceMeters;

  const NavInstruction._(
    this.kind,
    this.text,
    this.isCritical, {
    this.distanceMeters,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NavInstruction && other.kind == kind && other.text == text);

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => text;
}


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
    return NavInstruction._(
      NavInstructionKind.continueStraight,
      text,
      false,
      distanceMeters: metersRemaining,
    );
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


enum FacingCorrection { turnLeft, turnRight, turnAround }
