import 'package:flutter/widgets.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class CurrentUser extends InheritedWidget {
  const CurrentUser({
    super.key,
    required this.user,
    required super.child,
  });

  final Contact? user;

  static CurrentUser of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CurrentUser>()!;
  }

  @override
  bool updateShouldNotify(CurrentUser oldWidget) =>
      user?.id != oldWidget.user?.id;
}
