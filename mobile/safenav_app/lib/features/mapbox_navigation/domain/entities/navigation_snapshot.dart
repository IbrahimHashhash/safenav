import 'route_entity.dart';




class NavigationSnapshot {
  const NavigationSnapshot({
    required this.isNavigating,
    this.route,
    this.userLat,
    this.userLng,
    this.heading,
    this.destinationLat,
    this.destinationLng,
    this.destinationName,
    this.distanceToDestination,
    this.lastInstruction,
  });

  final bool isNavigating;
  final RouteEntity? route;

  
  final double? userLat;
  final double? userLng;

  
  final double? heading;

  final double? destinationLat;
  final double? destinationLng;
  final String? destinationName;

  final double? distanceToDestination;
  final String? lastInstruction;

  bool get hasUserLocation => userLat != null && userLng != null;

  static const NavigationSnapshot idle =
      NavigationSnapshot(isNavigating: false);

  NavigationSnapshot copyWith({
    bool? isNavigating,
    RouteEntity? route,
    double? userLat,
    double? userLng,
    double? heading,
    double? destinationLat,
    double? destinationLng,
    String? destinationName,
    double? distanceToDestination,
    String? lastInstruction,
  }) {
    return NavigationSnapshot(
      isNavigating: isNavigating ?? this.isNavigating,
      route: route ?? this.route,
      userLat: userLat ?? this.userLat,
      userLng: userLng ?? this.userLng,
      heading: heading ?? this.heading,
      destinationLat: destinationLat ?? this.destinationLat,
      destinationLng: destinationLng ?? this.destinationLng,
      destinationName: destinationName ?? this.destinationName,
      distanceToDestination:
          distanceToDestination ?? this.distanceToDestination,
      lastInstruction: lastInstruction ?? this.lastInstruction,
    );
  }
}
