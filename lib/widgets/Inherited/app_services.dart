/// App-wide service graph exposed via InheritedWidget.
///
/// Screens that want the whole bundle do
/// `AppServicesProvider.maybeOf(context)?.chatService`. Most
/// screens take the services they need through their constructor —
/// this provider is the root handoff, not a runtime DI container.
library vartalap.widgets.Inherited.app_services;

import 'package:flutter/widgets.dart';
import 'package:vartalap/main.dart' show AppServices;

class AppServicesProvider extends InheritedWidget {
  final AppServices services;
  const AppServicesProvider({
    super.key,
    required this.services,
    required super.child,
  });

  /// Null when there is no provider above [context] — screens rendered
  /// standalone (widget tests) take that path.
  static AppServices? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppServicesProvider>()
      ?.services;

  @override
  bool updateShouldNotify(AppServicesProvider old) =>
      !identical(old.services, services);
}
