import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'scenario.dart';

/// A scenario that does nothing automatically, allowing a user or test 
/// to take full manual control via the SimulatorController.
class ManualTakeoverScenario extends MockScenario {
  @override
  Future<void> onMessageSent(SimulatorController controller, RemoteMessage message) async {
    // Do nothing. Wait for manual trigger of simulateAck or simulateError.
  }

  @override
  Future<void> onProfileRequested(SimulatorController controller, String userId) async {
    // Do nothing.
  }

  @override
  Future<void> onChannelCreated(SimulatorController controller, ChannelPayload payload) async {
    // Do nothing.
  }
}
