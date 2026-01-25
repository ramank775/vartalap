import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vartalap/screens/chat/chat_info.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/widgets/avator.dart';
import 'package:vartalap/widgets/bouncing_dots.dart';
import 'package:vartalap/widgets/chatlist.dart';
import 'package:vartalap/widgets/notifier/iterable_notifier.dart';
import 'package:vartalap/widgets/message_input.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatScreen extends StatefulWidget {
  final ChatClient chat;
  ChatScreen(this.chat) : super(key: Key(chat.channel.id.toString()));

  @override
  ChatState createState() => ChatState();
}

class ChatState extends State<ChatScreen> with WidgetsBindingObserver {
  late final ChatClient chat;
  ChatMessageController _messageController =
      ChatMessageController(messages: []);
  final _selectedMessges = SetNotifier<int>(<int>{});
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showScrollToBottom = ValueNotifier<bool>(false);
  StreamSubscription? _notificationSub;
  StreamSubscription? _newMessageSub;
  Timer? _readTimer;
  Timer? _myTypingTimer;
  Timer? _remoteTypingTimer;
  final _typing = ValueNotifier<bool>(false);
  Set<ChatMessage> _unreadMessages = <ChatMessage>{};
  final Set<int> _loadingMessages = <int>{};

  @override
  void initState() {
    super.initState();
    chat = widget.chat;
    WidgetsBinding.instance.addObserver(this);
    chat.watch();
    
    _scrollController.addListener(() {
      if (_scrollController.offset > 200 && !_showScrollToBottom.value) {
        _showScrollToBottom.value = true;
      } else if (_scrollController.offset <= 200 && _showScrollToBottom.value) {
        _showScrollToBottom.value = false;
      }
    });

    // Listen for remote typing indicators
    _newMessageSub = chat.typingStream.listen((isTyping) {
      _typing.value = isTyping;
      
      // Auto-clear typing indicator after a timeout if no "stop" event received
      if (isTyping) {
        _remoteTypingTimer?.cancel();
        _remoteTypingTimer = Timer(const Duration(seconds: 5), () {
          _typing.value = false;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // These are the callbacks
    switch (state) {
      case AppLifecycleState.resumed:
        _notificationSub?.resume();
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(
          style: TextButton.styleFrom(
            shape: CircleBorder(),
            padding: const EdgeInsets.only(left: 1.0),
          ),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
          child: Row(
            children: <Widget>[
              Icon(
                Icons.arrow_back,
                size: 24.0,
                color: Colors.white,
              ),
              Avator(
                text: chat.displayName,
                width: 30.0,
                height: 30.0,
              )
              // new ProfileImg(this._chat.pic ?? 'assets/images/default-user.png',
              //     ProfileImgSize.SM),
            ],
          ),
        ),
        title: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ChatInfo(chat),
                ),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[_getTitle(context)],
            ),
          ),
        ),
        actions: _getActions(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            flex: 1,
            child: StreamBuilder<List<ChatMessage>>(
                stream: chat.messagesStream,
                builder: (context, snapshot) {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      );
                    case ConnectionState.waiting:
                      return Center(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.grey),
                        ),
                      );
                    case ConnectionState.active:
                    case ConnectionState.done:
                      if (snapshot.hasError) {
                        return Center(
                          child: Text('Error: ${snapshot.error}'),
                        );
                      }
                      if (_readTimer != null && _readTimer!.isActive) {
                        _readTimer!.cancel();
                      }
                      _readTimer = Timer(
                          Duration(milliseconds: 200), _onReadTimerTimeout);
                      final messages = snapshot.data ?? [];
                      // Track unread messages for read receipts
                      _unreadMessages.addAll(messages.where((msg) =>
                          msg.senderId != chat.currentUser.id &&
                          msg.state != MessageState.read));
                      _messageController =
                          ChatMessageController(messages: messages);
                      final Map<String, Member> members = {};
                      return Stack(
                        children: [
                          ChatList(
                            controller: _messageController,
                            members: members,
                            showName: chat.channel.type == ChannelType.group,
                            loadingMessages: _loadingMessages,
                            currentUser: chat.currentUser,
                            scrollController: _scrollController,
                            onTab: (ChatMessage msg) {
                              if (_selectedMessges.value.isNotEmpty) {
                                _selectOrRemove(msg);
                              }
                            },
                            onLongPress: (ChatMessage msg) {
                              if (_selectedMessges.value.isNotEmpty) {
                                _selectOrRemove(msg);
                              } else {
                                _showMessageContextMenu(context, msg);
                              }
                            },
                          ),
                          ValueListenableBuilder<bool>(
                            valueListenable: _showScrollToBottom,
                            builder: (context, show, child) {
                              if (!show) return const SizedBox.shrink();
                              return Positioned(
                                bottom: 16,
                                right: 16,
                                child: FloatingActionButton.small(
                                  onPressed: () {
                                    _scrollController.animateTo(
                                      0,
                                      duration: const Duration(milliseconds: 300),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                  child: const Icon(Icons.arrow_downward),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                  }
                }),
          ),
          ...chat.hasSendMessagePermission()
              ? [
                  MessageInputWidget(
                    sendMessage: (String text) async {
                      final msg = ChatMessage.text(
                        channelId: chat.channel.id,
                        senderId: chat.currentUser.id,
                        text: text,
                      ).copyWith(sender: chat.currentUser);

                      try {
                        // The UI simply requests to send the message.
                        // The client/DAO handles the DB insertion, 
                        // which triggers the reactive messagesStream.
                        await chat.sendMessage([msg]);
                      } catch (e) {
                        _showErrorSnackBar('Failed to send message: $e');
                      }
                    },
                    sendAttachment: (String path, String category) async {
                      try {
                        await chat.sendAttachment(path, category);
                      } catch (e) {
                        _showErrorSnackBar('Failed to send attachment: $e');
                      }
                    },
                    onTyping: (bool state) async {
                      if (state) {
                        if (!(_myTypingTimer?.isActive ?? false)) {
                          await chat.sendTypingIndicator(true);
                          _myTypingTimer = Timer.periodic(const Duration(seconds: 3),
                              (Timer timer) {
                            chat.sendTypingIndicator(true);
                          });
                        }
                      } else {
                        await chat.sendTypingIndicator(false);
                        if (_myTypingTimer?.isActive ?? false) {
                          _myTypingTimer!.cancel();
                        }
                        _myTypingTimer = null;
                      }
                    },
                  )
                ]
              : [],
        ],
      ),
    );
  }

  Widget _getTitle(BuildContext context) {
    return ValueListenableBuilder<Iterable<int>>(
      valueListenable: _selectedMessges,
      builder: (BuildContext context, Iterable<int> selectedMessages,
          Widget? child) {
        final subtitle = _getSubTitle();
        final titleWidgets = <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Text(
              _selectedMessges.value.isNotEmpty
                  ? "${_selectedMessges.value.length} selected"
                  : chat.displayName,
              style: TextStyle(
                fontSize: 18.0,
                color: Colors.white,
              ),
            ),
          ),
        ];
        if (_selectedMessges.value.isEmpty && subtitle.isNotEmpty) {
          titleWidgets.add(
            SizedBox(
                width: MediaQuery.of(context).size.width * 0.60,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _typing,
                  builder: (BuildContext context, bool state, Widget? child) {
                    var value = subtitle;
                    if (state) {
                      return Row(
                        children: [
                          const Text(
                            "typing",
                            style: TextStyle(fontSize: 12.0, color: Colors.white),
                          ),
                          const SizedBox(width: 4),
                          const BouncingDots(),
                        ],
                      );
                    }
                    return Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: const TextStyle(
                        fontSize: 12.0,
                        color: Colors.white,
                      ),
                    );
                  },
                )),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: titleWidgets,
        );
      },
    );
  }

  String _getSubTitle() {
    return chat.displayName;
  }

  void _selectOrRemove(ChatMessage msg) {
    if (!_selectedMessges.value.remove(msg.id)) {
      _selectedMessges.value.add(msg.id);
    }
    msg.isSelected = !msg.isSelected;
    _messageController.update(msg);
    _selectedMessges.update();
  }

  List<Widget> _getActions() {
    Widget child = ValueListenableBuilder(
      valueListenable: _selectedMessges,
      builder: (context, key, child) {
        List<Widget> actions = [];
        if (_selectedMessges.value.isNotEmpty) {
          actions.add(IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              List<ChatMessage> msgs = [];
              for (var id in _selectedMessges.value) {
                final notifier = _messageController.messageChangeNotifier[id];
                if (notifier != null) {
                  notifier.value.isSelected = false;
                  msgs.add(notifier.value);
                }
              }
              _messageController.updateAll(msgs);
              _selectedMessges.value.clear();
              _selectedMessges.update();
            },
          ));
          actions.add(IconButton(
            icon: Icon(Icons.delete),
            onPressed: () async {
              final selectedIds = _selectedMessges.value.toList();
              // Show confirmation dialog for bulk delete
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text('Delete Messages'),
                    content: Text(
                        'Are you sure you want to delete ${selectedIds.length} message(s)? This action cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style:
                            TextButton.styleFrom(foregroundColor: Colors.red),
                        child: Text('Delete'),
                      ),
                    ],
                  );
                },
              );

              if (confirmed == true) {
                try {
                  // Delete messages from server
                  for (final messageId in selectedIds) {
                    await chat.deleteMessage(messageId);
                  }
                  // Remove from UI
                  _messageController.deleteAll(selectedIds);
                  _selectedMessges.value.clear();
                  _selectedMessges.update();
                  _showSuccessSnackBar(
                      '${selectedIds.length} message(s) deleted successfully');
                } catch (e) {
                  _showErrorSnackBar('Failed to delete messages: $e');
                }
              }
            },
          ));
        }
        actions.add(PopupMenuButton(itemBuilder: (BuildContext context) => []));
        return Row(children: actions);
      },
    );
    return [child];
  }

  Future<void> _onReadTimerTimeout() async {
    if (_unreadMessages.isEmpty) return;
    _unreadMessages = <ChatMessage>{};

    try {
      // Mark all visible messages as read
      await chat.markAsRead();
    } catch (e) {
      // Silently handle read receipt errors
      debugPrint('Failed to mark messages as read: $e');
    }

    if (_unreadMessages.isNotEmpty &&
        (_readTimer == null || !_readTimer!.isActive)) {
      _readTimer = Timer(Duration(milliseconds: 100), _onReadTimerTimeout);
    }
  }

  void _showMessageContextMenu(BuildContext context, ChatMessage message) {
    final isMyMessage = message.senderId == chat.currentUser.id;
    final isTextMessage = message.type == MessageType.text;

    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTextMessage)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copy Text'),
                  onTap: () {
                    Navigator.pop(context);
                    Clipboard.setData(ClipboardData(text: message.text));
                    _showSuccessSnackBar('Text copied to clipboard');
                  },
                ),
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(context);
                  _showErrorSnackBar('Forwarding is not yet implemented');
                },
              ),
              if (isMyMessage && isTextMessage)
                ListTile(
                  leading: Icon(Icons.edit),
                  title: Text('Edit Message'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditMessageDialog(context, message);
                  },
                ),
              if (isMyMessage)
                ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text('Delete Message',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmationDialog(context, message);
                  },
                ),
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Message Info'),
                onTap: () {
                  Navigator.pop(context);
                  _showMessageInfo(context, message);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEditMessageDialog(BuildContext context, ChatMessage message) {
    if (message.type != MessageType.text) return;

    final textController = TextEditingController(text: message.text);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Message'),
          content: TextField(
            controller: textController,
            decoration: InputDecoration(
              hintText: 'Enter your message',
              border: OutlineInputBorder(),
            ),
            maxLines: null,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final newText = textController.text.trim();
                if (newText.isEmpty || newText == message.text) {
                  Navigator.pop(context);
                  return;
                }

                Navigator.pop(context);
                await _editMessage(message.id, newText);
              },
              child: Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmationDialog(
      BuildContext context, ChatMessage message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Delete Message'),
          content: Text(
              'Are you sure you want to delete this message? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deleteMessage(message.id);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showMessageInfo(BuildContext context, ChatMessage message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Message Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sent: ${_formatDateTime(message.timestamp)}'),
              if (message.updatedAt != message.timestamp)
                Text('Edited: ${_formatDateTime(message.updatedAt)}'),
              Text('Status: ${_getMessageStatusText(message.state)}'),
              Text('Type: ${message.type.toString().split('.').last}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editMessage(int messageId, String newText) async {
    setState(() {
      _loadingMessages.add(messageId);
    });

    try {
      await chat.editMessage(messageId, newText);
      _showSuccessSnackBar('Message edited successfully');
    } catch (e) {
      _showErrorSnackBar('Failed to edit message: $e');
    } finally {
      setState(() {
        _loadingMessages.remove(messageId);
      });
    }
  }

  Future<void> _deleteMessage(int messageId) async {
    setState(() {
      _loadingMessages.add(messageId);
    });

    try {
      await chat.deleteMessage(messageId);
      _messageController.delete(messageId);
      _showSuccessSnackBar('Message deleted successfully');
    } catch (e) {
      _showErrorSnackBar('Failed to delete message: $e');
    } finally {
      setState(() {
        _loadingMessages.remove(messageId);
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getMessageStatusText(MessageState state) {
    switch (state) {
      case MessageState.pending:
        return 'Sending...';
      case MessageState.sent:
        return 'Sent';
      case MessageState.delivered:
        return 'Delivered';
      case MessageState.read:
        return 'Read';
      case MessageState.error:
        return 'Error';
      case MessageState.other:
        return 'Unknown';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_readTimer?.isActive ?? false) _readTimer!.cancel();
    if (_myTypingTimer?.isActive ?? false) _myTypingTimer!.cancel();
    if (_remoteTypingTimer?.isActive ?? false) _remoteTypingTimer!.cancel();
    _notificationSub?.cancel();
    _newMessageSub?.cancel();
    _scrollController.dispose();
    _showScrollToBottom.dispose();
    _messageController.dispose();
    chat.dispose();
    super.dispose();
  }
}
