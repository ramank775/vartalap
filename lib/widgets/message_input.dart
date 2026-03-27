import 'dart:async';
import 'dart:io' as dart_io;

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:vartalap/widgets/Inherited/current_user.dart';
import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class MessageInputWidget extends StatefulWidget {
  final Function sendMessage;
  final Function(String path, String category)? sendAttachment;
  final Function(bool state)? onTyping;
  final ChatMessage? replyingTo;
  final VoidCallback? onCancelReply;
  
  const MessageInputWidget({
    super.key,
    required this.sendMessage,
    this.sendAttachment,
    this.onTyping,
    this.replyingTo,
    this.onCancelReply,
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
  void sendMessage() {
    var text = _controller.text;
    if (text.isEmpty && !_isRecording) {
      _startRecording();
      return;
    }
    
    if (text.isNotEmpty) {
      _sendMessage(text);
      _controller.text = "";
      setState(() {
        _isTextFieldEmpty = true;
      });
      if (_isShowSticker) {
        setState(() {
          _isShowSticker = false;
        });
      }
    }
  }

  // --- Voice Recording Logic ---
  
  RecorderController recorderController = RecorderController();
  bool _isTextFieldEmpty = true;
  bool _isRecording = false;
  String? _audioPath;

  @override
  void initState() {
    super.initState();
    _sendMessage = widget.sendMessage;
    _isShowSticker = false;
    _inputFocus = FocusNode();
    _inputFocus.addListener(onFocusListener);
    _controller.addListener(onTypingListener);
    _controller.addListener(() {
      if (_controller.text.isEmpty != _isTextFieldEmpty) {
        setState(() {
          _isTextFieldEmpty = _controller.text.isEmpty;
        });
      }
    });

    _initialiseControllers();
  }

  void _initialiseControllers() {
    recorderController = RecorderController();
  }

  @override
  void dispose() {
    super.dispose();
    recorderController.dispose();
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _inputFocus.removeListener(onFocusListener);
    _controller.removeListener(onTypingListener);
    _inputFocus.dispose();
    _controller.dispose();
  }

  void _startRecording() async {
    try {
      final hasPermission = await recorderController.checkPermission();
      if (!hasPermission) {
        debugPrint("No microphone permission");
        return;
      }

      final directory = await path_provider.getApplicationDocumentsDirectory();
      _audioPath = '${directory.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await recorderController.record(path: _audioPath!);
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      debugPrint("Failed to start recording: $e");
    }
  }

  void _stopAndSendRecording() async {
    try {
      final path = await recorderController.stop();
      setState(() {
        _isRecording = false;
      });
      if (path != null && widget.sendAttachment != null) {
        // Send as an audio note instead of generic document
        widget.sendAttachment!(path, 'audio');
      }
    } catch (e) {
      debugPrint("Failed to stop/send recording: $e");
    }
  }

  void _cancelRecording() async {
    try {
      await recorderController.stop();
      setState(() {
        _isRecording = false;
      });
      // Optionally delete the file if path exists
      if (_audioPath != null) {
         final file = dart_io.File(_audioPath!);
         if (await file.exists()) {
           await file.delete();
         }
      }
    } catch (e) {
      debugPrint("Failed to cancel recording: $e");
    }
  }

  // --- End Voice Recording Logic ---

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
      return Future.value(false);
    }
    return Future.value(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isShowSticker,
      onPopInvokedWithResult: onBackPress,
      child: Column(
        children: <Widget>[
          if (widget.replyingTo != null) _buildReplyPreview(),
          _isRecording ? buildRecordingInput(context) : buildInput(context), 
          buildSticker(context)
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColorLight,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
          left: BorderSide(color: Theme.of(context).primaryColor, width: 4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.replyingTo?.senderId == CurrentUser.of(context).user?.id
                      ? 'You'
                      : widget.replyingTo?.sender?.displayName ?? 'Unknown',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Text(
                  widget.replyingTo?.previewContent ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: widget.onCancelReply,
          ),
        ],
      ),
    );
  }

  Widget buildRecordingInput(BuildContext context) {
     var theme = Theme.of(context);
     return Row(
       mainAxisSize: MainAxisSize.max,
       children: [
         Flexible(
           flex: 1,
           child: Container(
             padding: const EdgeInsets.symmetric(horizontal: 10),
             decoration: BoxDecoration(
               color: theme.primaryColorLight,
             ),
             child: Row(
               children: [
                 IconButton(
                   icon: const Icon(Icons.delete, color: Colors.grey),
                   onPressed: _cancelRecording,
                 ),
                 Expanded(
                   child: AudioWaveforms(
                     size: Size(MediaQuery.of(context).size.width, 45),
                     recorderController: recorderController,
                     enableGesture: true,
                     waveStyle: WaveStyle(
                       waveColor: theme.primaryColor,
                       extendWaveform: true,
                       showMiddleLine: false,
                     ),
                   ),
                 ),
                 IconButton(
                   icon: Icon(Icons.send_rounded, color: theme.primaryColor),
                   onPressed: _stopAndSendRecording,
                 )
               ]
             )
           )
         )
       ]
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
                  icon: Icon(
                    _isTextFieldEmpty ? Icons.mic : Icons.send_rounded,
                  ),
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
}
