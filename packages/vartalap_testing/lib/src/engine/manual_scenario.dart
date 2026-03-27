import 'package:vartalap_messaging/vartalap_messaging.dart';
import 'scenario.dart';

/// A scenario that does nothing automatically, allowing full manual control
/// via the SimulatorController.
class ManualTakeoverScenario extends MockScenario {
  @override
  Future<void> onMessageSent(
      SimulatorController controller, RemoteMessage message) async {}

  @override
  Future<void> onProfileRequested(
      SimulatorController controller, String userId) async {}

  @override
  Future<void> onChannelCreated(
      SimulatorController controller, ChannelPayload payload) async {}

  @override
  Future<void> onProfileUpdated(SimulatorController controller,
      Map<String, dynamic> updates) async {}

  @override
  Future<void> onChannelUpdated(SimulatorController controller,
      String channelId, Map<String, dynamic> updates) async {}

  @override
  Future<void> onMembersAdded(SimulatorController controller,
      String channelId, List<String> memberIds) async {}

  @override
  Future<void> onMemberRemoved(SimulatorController controller,
      String channelId, String memberId) async {}
}
