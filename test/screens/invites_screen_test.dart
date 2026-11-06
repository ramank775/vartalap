/// Invite-only screens (decisions 219-221): the Invites row and list,
/// the bar in a 1:1 chat that is not connected yet, Report, and
/// Settings › Privacy's blocked list. Checked against a recording
/// [ChatService]: the store and the server have tests of their own.
library vartalap.screens.invites_screen_test;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/invites/invites.dart';
import 'package:vartalap/screens/settings/privacy.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_store/vartalap_store.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

const _self = '0aaaaaaa1';
const _ravi = '0bbbbbbb2';
const _group = '01efabcd-7000-8000-8abc-000000000001';

PeerLink _link({
  bool connected = false,
  bool blocked = false,
  bool sent = false,
  bool received = false,
}) =>
    (
      connected: connected,
      blocked: blocked,
      inviteSent: sent,
      inviteReceived: received,
    );

void main() {
  final fromRavi = InviteRow(
      channelId: dmChannelId(_ravi, _self),
      toUser: _self,
      fromUser: _ravi,
      createdAt: 1);
  const toFamily = InviteRow(
      channelId: _group,
      toUser: _self,
      fromUser: _ravi,
      name: 'Family',
      createdAt: 2);
  // ours, to someone else: not for the row
  const outgoing = InviteRow(
      channelId: 'd1', toUser: _ravi, fromUser: _self, createdAt: 3);

  testWidgets('the Invites row counts what is waiting, and hides at none',
      (tester) async {
    final chat = _FakeChatService(invites: [fromRavi, toFamily, outgoing]);
    await tester.pumpWidget(_app(InvitesRow(
        chatService: chat, authService: _FakeAuthService())));
    await tester.pumpAndSettle();
    expect(find.text('Invites (2)'), findsOneWidget);
    expect(find.text('2 people want to chat with you'), findsOneWidget);

    await tester.pumpWidget(_app(InvitesRow(
        key: UniqueKey(),
        chatService: _FakeChatService(invites: [outgoing]),
        authService: _FakeAuthService())));
    await tester.pumpAndSettle();
    expect(find.textContaining('Invites'), findsNothing);
  });

  testWidgets('the list: a person and a group, Decline and Decline and block',
      (tester) async {
    final chat = _FakeChatService(invites: [fromRavi, toFamily]);
    await tester.pumpWidget(_app(InvitesScreen(
        chatService: chat, authService: _FakeAuthService())));
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
    expect(find.text('Wants to chat with you'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Ravi invited you to this group'), findsOneWidget);

    await tester.tap(find.text('Decline').first);
    await tester.pumpAndSettle();
    expect(chat.calls, ['decline(${fromRavi.channelId}, false)']);

    await tester.tap(find.text('Decline and block').last);
    await tester.pumpAndSettle();
    expect(find.text('Block Ravi?'), findsOneWidget);
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(chat.calls.last, 'decline($_group, true)');
  });

  testWidgets('an invite taken back says so in plain words', (tester) async {
    final chat = _FakeChatService(
        invites: [fromRavi],
        acceptError: const AuthClientException('acceptInvite', 404, null, null));
    await tester.pumpWidget(_app(InvitesScreen(
        chatService: chat, authService: _FakeAuthService())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('This invite is no longer available.'), findsOneWidget);
  });

  group('the bar in a 1:1 chat', () {
    Future<_FakeChatService> pump(WidgetTester tester, PeerLink link) async {
      final chat = _FakeChatService();
      await tester.pumpWidget(_app(InviteBar(
        link: link,
        peerUserId: _ravi,
        peerName: 'Ravi',
        chatService: chat,
        authService: _FakeAuthService(),
      )));
      return chat;
    }

    final dm = dmChannelId(_self, _ravi);

    testWidgets('not connected: Send invite', (tester) async {
      final chat = await pump(tester, _link());
      expect(find.textContaining('Vartalap is invite only'), findsOneWidget);
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      expect(chat.calls, ['invite($_ravi)']);
    });

    testWidgets('invite sent: Cancel invite', (tester) async {
      final chat = await pump(tester, _link(sent: true));
      expect(find.text('Invite sent. You can chat once Ravi accepts.'),
          findsOneWidget);
      await tester.tap(find.text('Cancel invite'));
      await tester.pumpAndSettle();
      expect(chat.calls, ['cancel($dm, $_ravi)']);
    });

    testWidgets('invited: Accept, Decline, Decline and block', (tester) async {
      final chat = await pump(tester, _link(received: true));
      expect(find.text('Ravi wants to chat with you.'), findsOneWidget);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(chat.calls, ['accept($dm)']);
      expect(find.text('Decline and block'), findsOneWidget);
    });

    testWidgets('a cap reached is explained', (tester) async {
      final chat = await pump(tester, _link());
      chat.inviteError =
          const AuthClientException('sendInvite', 429, 'invite_limit', null);
      await tester.tap(find.text('Send invite'));
      await tester.pumpAndSettle();
      expect(find.textContaining('too many invites waiting'), findsOneWidget);
    });

    testWidgets('blocked: Unblock', (tester) async {
      final chat = await pump(tester, _link(connected: true, blocked: true));
      expect(find.text('You blocked Ravi.'), findsOneWidget);
      await tester.tap(find.text('Unblock'));
      await tester.pumpAndSettle();
      expect(chat.calls, ['block($_ravi, false)']);
    });
  });

  testWidgets('Report: with the last 5 messages, or without; and block',
      (tester) async {
    final chat = _FakeChatService();
    await tester.pumpWidget(_app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showReportDialog(context,
            chatService: chat, userId: _ravi, name: 'Ravi', channelId: 'd1'),
        child: const Text('report'),
      ),
    )));
    await tester.tap(find.text('report'));
    await tester.pumpAndSettle();
    expect(find.text('Report Ravi?'), findsOneWidget);
    await tester.tap(find.text('Report and block'));
    await tester.pumpAndSettle();
    expect(chat.calls, ['report($_ravi, d1, true)']);
    expect(find.text('Reported and blocked'), findsOneWidget);

    await tester.tap(find.text('report'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(chat.calls.last, 'report($_ravi, null, false)');
  });

  testWidgets('Settings › Privacy › Blocked contacts, with Unblock',
      (tester) async {
    final chat = _FakeChatService(blocked: {_ravi});
    await tester.pumpWidget(_app(BlockedContactsRow(chatService: chat)));
    await tester.pumpAndSettle();
    expect(find.text('Blocked contacts'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await tester.tap(find.text('Blocked contacts'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(chat.calls, ['block($_ravi, false)']);
  });
}

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: Material(child: child)));

class _FakeChatService implements ChatService {
  final List<String> calls = [];
  final List<InviteRow> invites;
  final Set<String> blocked;
  final Object? acceptError;
  Object? inviteError;

  _FakeChatService({
    this.invites = const [],
    this.blocked = const {},
    this.acceptError,
  });

  @override
  Stream<List<InviteRow>> watchInvites() => Stream.value(invites);

  @override
  Stream<Set<String>> watchBlocked() => Stream.value(blocked);

  @override
  Future<List<ContactRow>> discoverContacts({
    List<String> normalizedPhones = const [],
    Map<String, String> contactBookNamesByPhone = const {},
  }) async =>
      [
        ContactRow(
          userId: _ravi,
          username: 'ravi',
          displayName: null,
          avatarUrl: null,
          statusText: null,
          phoneHash: null,
          contactBookName: 'Ravi',
          lastRefreshedMs: 0,
        ),
      ];

  @override
  Future<String> acceptInvite(InviteRow invite) async {
    calls.add('accept(${invite.channelId})');
    if (acceptError case final e?) throw e;
    return invite.channelId;
  }

  @override
  Future<void> declineInvite(InviteRow invite, {bool block = false}) async {
    calls.add('decline(${invite.channelId}, $block)');
  }

  @override
  Future<void> sendInvite(String peerUserId) async {
    if (inviteError case final e?) throw e;
    calls.add('invite($peerUserId)');
  }

  @override
  Future<void> cancelInvite(String channelId, String userId) async {
    calls.add('cancel($channelId, $userId)');
  }

  @override
  Future<void> setBlocked(String userId, bool blocked) async {
    calls.add('block($userId, $blocked)');
  }

  @override
  Future<void> report(String userId,
      {String? channelId, bool block = false}) async {
    calls.add('report($userId, $channelId, $block)');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeAuthService implements AuthService {
  @override
  String? get currentUserId => _self;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
