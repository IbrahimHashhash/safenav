import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/navigation_service.dart';
import '../../domain/entities/navigation_snapshot.dart';



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
