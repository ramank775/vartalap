import 'package:flutter/material.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class VartalapClientProvider extends InheritedWidget {
  const VartalapClientProvider({
    Key? key,
    required this.client,
    required Widget child,
  }) : super(key: key, child: child);

  final VartalapChatClientFlutter client;

  static VartalapClientProvider of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<VartalapClientProvider>()!;
  }

  @override
  bool updateShouldNotify(VartalapClientProvider oldWidget) => false;
}
