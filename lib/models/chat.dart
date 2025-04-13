import 'package:vartalap_messaging_flutter/vartalap_messaging_flutter.dart';

class ChatPreview {
  Channel channel;
  String _content = '';
  int _ts = 0;
  int _unread = 0;
  ChatPreview(this.channel, this._content, this._ts, this._unread);

  String get content => this._content;
  int get ts => this._ts;
  int get unread => this._unread;
}
