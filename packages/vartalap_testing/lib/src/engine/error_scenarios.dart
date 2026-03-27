import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'scenario.dart';

/// All messages fail with an error ack
class NetworkErrorScenario extends MockScenario {
  final String errorMessage;
  final Duration delay;

  NetworkErrorScenario({
    this.errorMessage = 'Network error',
    this.delay = const Duration(milliseconds: 200),
  });

  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {
    await Future.delayed(delay);
    controller.simulateError(message.id, errorMessage);
  }
}

/// Messages never receive any ack — simulates being fully offline
class OfflineScenario extends MockScenario {
  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {
    // No response at all — message stays pending forever
  }
}

/// Some messages succeed, some fail based on a failure rate
class PartialFailureScenario extends MockScenario {
  final double failureRate;
  int _messageCount = 0;

  PartialFailureScenario({this.failureRate = 0.5});

  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {
    _messageCount++;
    final shouldFail =
        (_messageCount % (1 / failureRate).round()) == 0;

    if (shouldFail) {
      await Future.delayed(const Duration(milliseconds: 100));
      controller.simulateError(message.id, 'Simulated failure');
    } else {
      await controller.simulateAck(message.id, 'sent',
          delay: const Duration(milliseconds: 50));
      await controller.simulateAck(message.id, 'delivered',
          delay: const Duration(milliseconds: 100));
    }
  }
}

/// Messages succeed but with high latency
class SlowNetworkScenario extends MockScenario {
  final Duration latency;

  SlowNetworkScenario({this.latency = const Duration(seconds: 5)});

  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {
    await controller.simulateAck(message.id, 'sent', delay: latency);
    await controller.simulateAck(message.id, 'delivered', delay: latency);
  }
}
