/// App-wide service graph exposed via InheritedWidget.
///
/// Screens that want the whole bundle do
/// `AppServicesProvider.of(context).services.chatService`. Most
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

  static AppServicesProvider of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppServicesProvider>();
    if (provider == null) {
      throw StateError('AppServicesProvider not found in context');
    }
    return provider;
  }

  @override
  bool updateShouldNotify(AppServicesProvider old) =>
      !identical(old.services, services);
}
