import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MessageInputWidget extends StatefulWidget {
  final Function sendMessage;
  final Function(String path, String category)? sendAttachment;
  final Function(bool state)? onTyping;
  const MessageInputWidget({
    super.key,
    required this.sendMessage,
    this.sendAttachment,
    this.onTyping,
  });

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInputWidget> {
  final ImagePicker _picker = ImagePicker();
  late Function _sendMessage;
  bool _isShowSticker = false;
  FocusNode _inputFocus = FocusNode();
  Timer? _typingTimer;
  final TextEditingController _controller = TextEditingController();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null && widget.sendAttachment != null) {
      widget.sendAttachment!(image.path, 'image');
    }
  }

  Future<void> _pickVideo() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video != null && widget.sendAttachment != null) {
      widget.sendAttachment!(video.path, 'video');
    }
  }

  Future<void> _pickDocument() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null && widget.sendAttachment != null) {
      widget.sendAttachment!(result.files.single.path!, 'document');
    }
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Document'),
                onTap: () {
                  Navigator.pop(context);
                  _pickDocument();
                },
              ),
            ],
          ),
        );
      },
    );
  }
  @override
  void initState() {
    super.initState();
    _sendMessage = widget.sendMessage;
    _isShowSticker = false;
    _inputFocus = FocusNode();
    _inputFocus.addListener(onFocusListener);
    _controller.addListener(onTypingListener);
  }

  @override
  void dispose() {
    super.dispose();
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _inputFocus.removeListener(onFocusListener);
    _controller.removeListener(onTypingListener);
    _inputFocus.dispose();
    _controller.dispose();
  }

  void onTypingListener() {
    if (_controller.text.isEmpty) return;
    if (_typingTimer == null) {
      widget.onTyping?.call(true);
    }
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(Duration(seconds: 3), onTypingTimeout);
  }

  void onTypingTimeout() {
    widget.onTyping?.call(false);
    _typingTimer = null;
  }

  void onFocusListener() {
    if (_isShowSticker && _inputFocus.hasFocus) {
      setState(() {
        _isShowSticker = false;
      });
    }
  }

  Future<bool> onBackPress(bool pop, bool? result) {
    if (_isShowSticker) {
      setState(() {
        _isShowSticker = false;
      });
      // Intercepted: consumed by closing the emoji panel, don't pop
      return Future.value(false);
    }
    // Not intercepting — let the system/AppBar back button handle the pop
    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Allow natural pops (AppBar back button); only intercept when emoji panel is open
      canPop: !_isShowSticker,
      onPopInvokedWithResult: onBackPress,
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
    return Row(
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
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _showAttachmentMenu,
                ),
                IconButton(
                  onPressed: sendMessage,
                  icon: const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildSticker(BuildContext context) {
    return Offstage(
      offstage: !_isShowSticker,
      child: SizedBox(
        height: 250,
        child: EmojiPicker(
          onEmojiSelected: (category, emoji) {
            _controller.text += emoji.emoji;
          },
          config: Config(),
        ),
      ),
    );
  }

  void sendMessage() {
    var text = _controller.text;
    if (text.isEmpty) {
      return;
    }
    _sendMessage(text);
    _controller.text = "";
    if (_isShowSticker) {
      setState(() {
        _isShowSticker = false;
      });
    }
  }
}
