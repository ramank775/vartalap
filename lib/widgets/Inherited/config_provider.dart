import 'package:flutter/widgets.dart';
import 'package:vartalap/config/config_store.dart';

class ConfigProvider extends InheritedWidget {
  const ConfigProvider({
    super.key,
    required this.configStore,
    required super.child,
  });

  final ConfigStore configStore;

  static ConfigProvider of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ConfigProvider>()!;
  }

  @override
  bool updateShouldNotify(ConfigProvider oldWidget) => false;
}
