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
  final Function(ChatMessage)? onReply;
  final Map<String, Member> members;
  final Set<int>? loadingMessages;
  final Contact? currentUser;
  final ScrollController? scrollController;

  const ChatList({
    super.key,
    required this.controller,
    required this.members,
    this.showName = false,
    this.onLongPress,
    this.onTab,
    this.onReply,
    this.loadingMessages,
    this.currentUser,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final currentUser = this.currentUser ?? CurrentUser.of(context).user!;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (BuildContext context, List<ChatMessage> value, Widget? child) {
        final result = calculateChatMessages(
          value,
          currentUser,
          showUserNames: showName,
        );
        final displayMessages = result[0] as List<Object>;
        debugPrint('[UI] ChatList rendering ${displayMessages.length} items (from ${value.length} messages)');
        return ListView.builder(
          controller: scrollController,
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
      bool isYou = msg.senderId == currentUser.id;
      bool showUserInfo = !isYou && this.showName && showName;

      final notifier = controller.getNewNotifier(msg);
      final isLoading = loadingMessages?.contains(msg.id) ?? false;
      
      ChatMessage? replyToMessage;
      if (msg.replyTo != null) {
        final idx = controller.value.indexWhere((m) => m.id == msg.replyTo);
        if (idx != -1) {
          replyToMessage = controller.value[idx];
        } else {
          // If it's not in the current list, try fetching it from DB later 
          // (For now will just not render reply content if not loaded)
        }
      }

      Widget child = ValueListenableBuilder<ChatMessage>(
        builder: (context, key, child) {
          return Dismissible(
            key: Key('msg_${msg.id}'),
            direction: DismissDirection.startToEnd,
            confirmDismiss: (direction) async {
              // Trigger reply callback if defined
              if (onReply != null) {
                onReply!(msg);
              }
              return false; // Never actually dismiss the widget
            },
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20.0),
              color: Colors.transparent,
              child: const Icon(Icons.reply, color: Colors.grey),
            ),
            child: MessageWidget(
              msg,
              isYou,
              showUserInfo: showUserInfo,
              isSelected: msg.isSelected,
              showNip: showNip,
              isLoading: isLoading,
              onTab: onTab,
              onLongPress: onLongPress,
              replyToMessage: replyToMessage,
            ),
          );
        },
        valueListenable: notifier,
      );

      return child;
    }
    return const SizedBox();
  }
}
