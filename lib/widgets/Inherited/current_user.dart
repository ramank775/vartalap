import 'package:flutter/widgets.dart';
import 'package:vartalap/models/user.dart';

class CurrentUser extends InheritedWidget {
  CurrentUser({
    Key? key,
    required this.user,
    required Widget child,
  }) : super(key: key, child: child);

  final User? user;

  static CurrentUser of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<CurrentUser>()!;
  }

  @override
  bool updateShouldNotify(CurrentUser oldWidget) =>
      user?.username != oldWidget.user?.username;
}
