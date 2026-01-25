import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:vartalap/config/app_config.dart';
import 'package:vartalap/screens/profile/profile.dart';
import 'package:vartalap/services/vartalap_authenticated_client.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';
import 'package:vartalap_testing/vartalap_testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockVartalapChatClient mockMessagingClient;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Vartalap Test',
      packageName: 'com.one9x.vartalap.test',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: 'buildSignature',
    );
    await AppConfig.initialize();

    mockMessagingClient = MockVartalapChatClient(
      tokenManager: MockTokenManager(),
    );
  });

  group('ProfileScreen Widget Tests', () {
    testWidgets('Displays profile information', (tester) async {
      final testAuthClient = TestAuthClient(
          client: VartalapChatClientFlutter(
              apiKey: 'test', client: mockMessagingClient));
      testAuthClient.setUserExplicit(Profile(
        userId: '+1234567890',
        name: 'Test Tester',
        email: 'test@example.com',
        image: '',
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<VartalapAuthenticatedClient>.value(
          value: testAuthClient,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Test Tester'), findsOneWidget);
      expect(find.text('+1234567890'), findsAtLeastNWidgets(1));
    });

    testWidgets('Enables editing and saves changes', (tester) async {
      final testAuthClient = TestAuthClient(
          client: VartalapChatClientFlutter(
              apiKey: 'test', client: mockMessagingClient));
      testAuthClient.setUserExplicit(Profile(
        userId: '+1234567890',
        name: 'Old Name',
        email: 'test@example.com',
        image: '',
      ));

      await tester.pumpWidget(
        ChangeNotifierProvider<VartalapAuthenticatedClient>.value(
          value: testAuthClient,
          child: const MaterialApp(home: ProfileScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Tap Edit
      await tester.tap(find.byIcon(Icons.edit));
      await tester.pump();

      // Enter new name
      await tester.enterText(find.byType(TextField), 'New Name');

      // Tap Save
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(testAuthClient.currentUser?.name, 'New Name');
      expect(find.text('New Name'), findsOneWidget);
    });
  });
}

class TestAuthClient extends VartalapAuthenticatedClient {
  TestAuthClient({required super.client});

  @override
  Profile? get currentUser => _testUser;
  Profile? _testUser;

  void setUserExplicit(Profile p) {
    _testUser = p;
    notifyListeners();
  }

  @override
  Future<void> updateProfile({String? name, String? image}) async {
    if (_testUser != null) {
      _testUser = Profile(
        userId: _testUser!.userId,
        name: name ?? _testUser!.name,
        email: _testUser!.email,
        image: image ?? _testUser!.image,
      );
      notifyListeners();
    }
  }
}
