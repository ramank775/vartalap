import 'package:flutter/material.dart';
import 'package:vartalap/models/date_header.dart';
import 'package:vartalap/models/message_spacer.dart';
import 'package:vartalap/widgets/message.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatMessageController extends ValueNotifier<List<ChatMessage>> {
  final Map<int, ChatMessageNotifier> messageChangeNotifier = {};

  ChatMessageController({required List<ChatMessage> messages})
      : super(messages);

  ChatMessageNotifier getNewNotifier(ChatMessage msg) {
    var notifier = messageChangeNotifier[msg.id];
    if (notifier == null) {
      notifier = ChatMessageNotifier(msg);
      messageChangeNotifier[msg.id] = notifier;
    }

    return notifier;
  }

  void add(ChatMessage msg) {
    messageChangeNotifier[msg.id] = ChatMessageNotifier(msg);
    value.insert(0, msg);
    notifyListeners();
  }

  void addAll(Iterable<ChatMessage> msgs) {
    for (var msg in msgs) {
      messageChangeNotifier[msg.id] = ChatMessageNotifier(msg);
    }
    value.insertAll(0, msgs);
    notifyListeners();
  }

  void delete(int id) {
    value.removeWhere((msg) => msg.id == id);
    messageChangeNotifier.remove(id);
    notifyListeners();
  }

  void deleteAll(Iterable<int> ids) {
    value.removeWhere((ChatMessage msg) => ids.contains(msg.id));
    for (var id in ids) {
      messageChangeNotifier.remove(id);
    }
    notifyListeners();
  }

  void update(ChatMessage msg) {
    int idx = value.indexWhere((message) => message.id == msg.id);
    if (idx == -1) return;
    value[idx] = msg;
    final notifier = messageChangeNotifier[msg.id];
    if (notifier != null) {
      notifier.update(msg);
    }
  }

  void updateAll(Iterable<ChatMessage> msgs) {
    msgs.forEach(update);
  }

  @override
  void dispose() {
    super.dispose();
    for (var msgNotifier in messageChangeNotifier.values) {
      msgNotifier.dispose();
    }
  }
}

typedef MessageTapCallback = void Function(ChatMessage msg);
typedef MessageLongPressCallback = void Function(ChatMessage msg);

class ChatList extends StatelessWidget {
  final ChatMessageController controller;
  final bool showName;
  final MessageTapCallback? onTab;
  final MessageLongPressCallback? onLongPress;
  final Map<String, Member> members;
  final Set<int>? loadingMessages;
  final Contact? currentUser;

  const ChatList({
    super.key,
    required this.controller,
    required this.members,
    this.showName = false,
    this.onLongPress,
    this.onTab,
    this.loadingMessages,
    this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = this.currentUser ?? CurrentUser.of(context).user!;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (BuildContext context, List<ChatMessage> value, Widget? child) {
        final displayMessages = calculateChatMessages(
          value,
          currentUser,
          showUserNames: showName,
        )[0] as List<Object>;
        return ListView.builder(
          itemCount: displayMessages.length,
          reverse: true,
          itemBuilder: (context, i) {
            return _messageBuilder(displayMessages[i], currentUser);
          },
        );
      },
    );
  }

  Widget _messageBuilder(Object object, Contact currentUser) {
    if (object is DateHeader) {
      return Container(
        alignment: Alignment.center,
        margin: const EdgeInsets.only(
          bottom: 32,
          top: 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: VartalapTheme.theme.receiverColor,
            borderRadius: BorderRadius.all(
              Radius.circular(5),
            ),
          ),
          child: Text(
            object.date,
          ),
        ),
      );
    } else if (object is MessageSpacer) {
      return SizedBox(
        height: object.height,
      );
    } else if (object is Map) {
      ChatMessage msg = object["message"];
      bool showName = object["showName"];
      bool showNip = object["showNip"];
      bool isYou = msg.sender == currentUser;
      bool showUserInfo = !isYou && this.showName && showName;

      final notifier = controller.getNewNotifier(msg);
      final isLoading = loadingMessages?.contains(msg.id) ?? false;
      Widget child = ValueListenableBuilder<ChatMessage>(
        builder: (context, key, child) {
          return MessageWidget(
            msg,
            isYou,
            showUserInfo: showUserInfo,
            isSelected: msg.isSelected,
            showNip: showNip,
            isLoading: isLoading,
            onTab: onTab,
            onLongPress: onLongPress,
          );
        },
        valueListenable: notifier,
      );

      return child;
    }
    return const SizedBox();
  }
}
