import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';

class MessageInputWidget extends StatefulWidget {
  final Function sendMessage;
  final Function(bool state)? onTyping;
  MessageInputWidget({
    Key? key,
    required this.sendMessage,
    this.onTyping,
  }) : super(key: key);

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInputWidget> {
  late Function _sendMessage;
  bool _isShowSticker = false;
  FocusNode _inputFocus = FocusNode();
  Timer? _typingTimer;
  final TextEditingController _controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    _sendMessage = widget.sendMessage;
    _isShowSticker = false;
    _inputFocus = FocusNode();
    _inputFocus.addListener(onFocusListener);
    _controller.addListener(onTypingListener);
  }

  void dispose() {
    super.dispose();
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _inputFocus.removeListener(onFocusListener);
    _controller.removeListener(onTypingListener);
    _inputFocus.dispose();
    _controller.dispose();
  }

  void onTypingListener() {
    if (this._controller.text.isEmpty) return;
    if (_typingTimer == null) {
      this.widget.onTyping?.call(true);
    }
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(Duration(seconds: 3), onTypingTimeout);
  }

  void onTypingTimeout() {
    this.widget.onTyping?.call(false);
    _typingTimer = null;
  }

  void onFocusListener() {
    if (_isShowSticker && _inputFocus.hasFocus) {
      setState(() {
        _isShowSticker = false;
      });
    }
  }

  Future<bool> onBackPress() {
    if (_isShowSticker) {
      setState(() {
        _isShowSticker = false;
      });
    } else {
      Navigator.pop(context);
    }

    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: onBackPress,
      child: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[buildInput(context), buildSticker(context)],
          ),
        ],
      ),
    );
  }

  Widget buildInput(BuildContext context) {
    var theme = Theme.of(context);
    return Container(
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          Flexible(
            flex: 1,
            child: Container(
              decoration: BoxDecoration(
                color: theme.primaryColorLight,
                //borderRadius: BorderRadius.all(const Radius.circular(30.0)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    padding: const EdgeInsets.all(0.0),
                    icon: Icon(_isShowSticker
                        ? Icons.keyboard
                        : Icons.insert_emoticon_sharp),
                    onPressed: () {
                      _isShowSticker
                          ? _inputFocus.requestFocus()
                          : _inputFocus.unfocus();
                      setState(() {
                        _isShowSticker = !_isShowSticker;
                      });
                    },
                  ),
                  Flexible(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(0.0),
                        hintText: 'Type a message',
                        hintStyle: TextStyle(
                          fontSize: 16.0,
                        ),
                        counterText: '',
                      ),
                      onSubmitted: (String text) {
                        sendMessage();
                      },
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(
                        fontSize: 19,
                      ),
                      maxLines: null,
                      maxLength: TextField.noMaxLength,
                      focusNode: _inputFocus,
                    ),
                  ),
                  // IconButton(
                  //   icon: Icon(Icons.attach_file),
                  //   onPressed: () {},
                  // ),
                  IconButton(
                    onPressed: sendMessage,
                    icon: Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSticker(BuildContext context) {
    var theme = Theme.of(context);
    final vtheme = VartalapTheme.theme;
    return Offstage(
      offstage: !_isShowSticker,
      child: SizedBox(
        height: 250,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            _controller..text += emoji.emoji;
          },
          config: Config(
            columns: 8,
            emojiSizeMax: 25.0,
            verticalSpacing: 0,
            horizontalSpacing: 0,
            initCategory: Category.RECENT,
            bgColor: theme.scaffoldBackgroundColor,
            indicatorColor: theme.indicatorColor,
            recentsLimit: 28,
            enableSkinTones: true,
            categoryIcons: CategoryIcons(),
            buttonMode: ButtonMode.MATERIAL,
            iconColorSelected: vtheme.selectedRowColor,
          ),
        ),
      ),
    );
  }

  void sendMessage() {
    var text = this._controller.text;
    if (text.length == 0) {
      return;
    }
    _sendMessage(text);
    this._controller.text = "";
    if (_isShowSticker) {
      setState(() {
        _isShowSticker = false;
      });
    }
  }
}
