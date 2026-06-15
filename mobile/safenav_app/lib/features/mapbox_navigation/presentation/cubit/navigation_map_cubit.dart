import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/navigation_service.dart';
import '../../domain/entities/navigation_snapshot.dart';

/// Exposes the live [NavigationSnapshot] stream from [NavigationService] to the
/// widget tree. Pure presentation glue — holds no navigation logic itself.
class NavigationMapCubit extends Cubit<NavigationSnapshot> {
  NavigationMapCubit(this._service) : super(_service.currentSnapshot) {
    _sub = _service.snapshots.listen(emit);
  }

  final NavigationService _service;
  StreamSubscription<NavigationSnapshot>? _sub;

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
