import 'package:emoji_picker/emoji_picker.dart';
import 'package:flutter/material.dart';

class MessageInputWidget extends StatefulWidget {
  final Function sendMessage;
  MessageInputWidget({Key key, this.sendMessage}) : super(key: key);

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInputWidget> {
  Function _sendMessage;
  bool _isShowSticker;
  FocusNode _inputFocus;
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
            children: <Widget>[
              buildInput(),

              // Sticker
              (_isShowSticker ? buildSticker() : Container()),
            ],
          ),
        ],
      ),
    );
  }

  Widget buildInput() {
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
                  borderRadius: BorderRadius.all(const Radius.circular(30.0)),
                  color: Colors.white,
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      padding: const EdgeInsets.all(0.0),
                      // disabledColor: iconColor,
                      // color: iconColor,
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
                            // color: textFieldHintColor,
                            fontSize: 16.0,
                          ),
                          counterText: '',
                        ),
                        onSubmitted: (String text) {
                          sendMessage();
                        },
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                        maxLength: 100,
                        focusNode: _inputFocus,
                      ),
                    ),
                    IconButton(
                      // color: iconColor,
                      icon: Icon(Icons.attach_file),
                      onPressed: () {},
                    ),
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

  Widget buildSticker() {
    return EmojiPicker(
      rows: 4,
      columns: 10,
      buttonMode: ButtonMode.MATERIAL,
      numRecommended: 10,
      onEmojiSelected: (emoji, category) {
        _controller.text += emoji.emoji;
      },
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
