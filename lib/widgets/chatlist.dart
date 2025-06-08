import 'package:flutter/material.dart';
import 'package:vartalap/models/dateHeader.dart';
import 'package:vartalap/models/messageSpacer.dart';
import 'package:vartalap/widgets/message.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/chat_message_helper.dart';
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatMessageController extends ValueNotifier<List<ChatMessage>> {
  final Map<int, ChatMessageNotifier> messageChangeNotifier = {};

  ChatMessageController({required List<ChatMessage> messages})
      : super(messages);

  getNewNotifier(ChatMessage msg) {
    var notifier = this.messageChangeNotifier[msg.id];
    if (notifier == null) {
      notifier = ChatMessageNotifier(msg);
      this.messageChangeNotifier[msg.id] = notifier;
    }

    return notifier;
  }

  add(ChatMessage msg) {
    this.messageChangeNotifier[msg.id] = ChatMessageNotifier(msg);
    this.value.insert(0, msg);
    this.notifyListeners();
  }

  addAll(Iterable<ChatMessage> msgs) {
    msgs.forEach((msg) {
      this.messageChangeNotifier[msg.id] = ChatMessageNotifier(msg);
    });
    this.value.insertAll(0, msgs);
    this.notifyListeners();
  }

  delete(int id) {
    this.value.removeWhere((msg) => msg.id == id);
    this.messageChangeNotifier.remove(id);
    this.notifyListeners();
  }

  deleteAll(Iterable<int> ids) {
    this.value.removeWhere((ChatMessage msg) => ids.contains(msg.id));
    ids.forEach((id) {
      this.messageChangeNotifier.remove(id);
    });
    this.notifyListeners();
  }

  update(ChatMessage msg) {
    int idx = this.value.indexWhere((message) => message.id == msg.id);
    if (idx == -1) return;
    this.value[idx] = msg;
    final notifier = this.messageChangeNotifier[msg.id];
    if (notifier != null) {
      notifier.update(msg);
    }
  }

  updateAll(Iterable<ChatMessage> msgs) {
    msgs.forEach(this.update);
  }

  @override
  void dispose() {
    super.dispose();
    this.messageChangeNotifier.values.forEach((msgNotifier) {
      msgNotifier.dispose();
    });
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

  ChatList({
    super.key,
    required this.controller,
    required this.members,
    this.showName = false,
    this.onLongPress,
    this.onTab,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = CurrentUser.of(context).user!;
    return ValueListenableBuilder(
      valueListenable: this.controller,
      builder: (BuildContext context, List<ChatMessage> value, Widget? child) {
        final displayMessages = calculateChatMessages(
          value,
          currentUser,
          showUserNames: this.showName,
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

      final notifier = this.controller.getNewNotifier(msg);
      Widget child = ValueListenableBuilder<ChatMessage>(
        builder: (context, key, child) {
          return MessageWidget(
            msg,
            isYou,
            showUserInfo: showUserInfo,
            isSelected: msg.isSelected,
            showNip: showNip,
            onTab: this.onTab,
            onLongPress: this.onLongPress,
          );
        },
        valueListenable: notifier,
      );

      return child;
    }
    return const SizedBox();
  }
}
