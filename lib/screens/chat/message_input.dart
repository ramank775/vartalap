import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

class MessageInputWidget extends StatefulWidget {
  final Function sendMessage;
  MessageInputWidget({Key? key, required this.sendMessage}) : super(key: key);

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInputWidget> {
  late Function _sendMessage;
  bool _isShowSticker = false;
  FocusNode _inputFocus = FocusNode();
  final TextEditingController _controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    _sendMessage = widget.sendMessage;
    _isShowSticker = false;
    _inputFocus = FocusNode();
    _inputFocus.addListener(onFocusListener);
  }

  void dispose() {
    super.dispose();
    _inputFocus.removeListener(onFocusListener);
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
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            Flexible(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.primaryColorLight,
                  borderRadius: BorderRadius.all(const Radius.circular(30.0)),
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      padding: const EdgeInsets.all(0.0),
                      icon: Icon(_isShowSticker
                          ? Icons.keyboard
                          : Icons.insert_emoticon),
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
                        maxLines: null,
                        maxLength: TextField.noMaxLength,
                        focusNode: _inputFocus,
                      ),
                    ),
                    // IconButton(
                    //   icon: Icon(Icons.attach_file),
                    //   onPressed: () {},
                    // ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: IconButton(
                onPressed: sendMessage,
                icon: Icon(Icons.send),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget buildSticker(BuildContext context) {
    var theme = Theme.of(context);
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
            indicatorColor: theme.accentColor,
            showRecentsTab: true,
            recentsLimit: 28,
            noRecentsText: 'No Recents',
            noRecentsStyle: TextStyle(fontSize: 20),
            categoryIcons: CategoryIcons(),
            buttonMode: ButtonMode.MATERIAL,
            iconColorSelected: theme.selectedRowColor,
            progressIndicatorColor: theme.accentColor,
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
