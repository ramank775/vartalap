import 'package:flutter/widgets.dart';
import 'package:vartalap/config/config_store.dart';

class ConfigProvider extends InheritedWidget {
  ConfigProvider({
    Key? key,
    required this.configStore,
    required Widget child,
  }) : super(key: key, child: child);

  final ConfigStore configStore;

  static ConfigProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ConfigProvider>()!;
  }

  @override
  bool updateShouldNotify(ConfigProvider oldWidget) => false;
}
