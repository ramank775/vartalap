import 'package:vartalap_messaging/vartalap_messaging.dart';

/// Base class for defining server-side behavior scenarios
abstract class MockScenario {
  /// Called when the client sends a message to the "server"
  Future<void> onMessageSent(SimulatorController controller, RemoteMessage message) async {
    // Default: just acknowledge the message was sent
    await controller.simulateAck(message.id, 'sent');
  }

  /// Called when the client requests a profile
  Future<void> onProfileRequested(SimulatorController controller, String userId) async {}

  /// Called when the client requests to create a channel
  Future<void> onChannelCreated(SimulatorController controller, ChannelPayload payload) async {}
}

/// Interface for controlling the virtual server from a scenario or test
abstract class SimulatorController {
  /// Inject an incoming message as if it came from the server
  void injectMessage(RemoteMessage message);

  /// Simulate a status update for a specific message
  Future<void> simulateAck(String messageId, String status, {Duration delay = Duration.zero});

  /// Simulate a failure for a specific message
  void simulateError(String messageId, String errorMessage);

  /// Get the current user ID being mocked
  String get currentUserId;
}
