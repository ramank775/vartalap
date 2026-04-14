import 'dart:async';

import 'package:vartalap_store/vartalap_store.dart';

/// Reactive stream of user-visible outbound-op failures.
///
/// SPIKE_B_SYNC.md §10: the UI subscribes to this and renders an error
/// toast / inline retry affordance per entry. Acknowledgment (dismiss
/// or manual retry) sets `acknowledged_at`; GC removes the row after
/// 24 hours.
///
/// Emits immediately on subscribe, then re-emits on any `outbound_ops`
/// mutation. Filtering ("only emit when the failure list actually
/// changed") happens via `.distinct()` in the caller if they want it.
Stream<List<OutboundOpRow>> watchFailures(ChatStore store) {
  late StreamController<List<OutboundOpRow>> controller;
  StreamSubscription<Set<String>>? changeSub;

  Future<void> emit() async {
    if (controller.isClosed) return;
    controller.add(await store.fetchFailures());
  }

  controller = StreamController<List<OutboundOpRow>>(
    onListen: () {
      changeSub = store.tableChanges.listen((tables) {
        if (tables.contains('outbound_ops')) emit();
      });
      emit();
    },
    onCancel: () async {
      await changeSub?.cancel();
      changeSub = null;
    },
  );
  return controller.stream;
}
