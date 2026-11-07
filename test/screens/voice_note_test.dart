import 'package:flutter_test/flutter_test.dart';
import 'package:vartalap/screens/chat/voice_note.dart';
import 'package:vartalap_transport/vartalap_transport.dart';

void main() {
  test('the longest voice note fits the upload limit at the encoder bitrate',
      () {
    // Twice the audio, for the container and a recorder running over.
    final bytes = 2 * kMaxVoiceNote.inSeconds * kVoiceNoteBitRate ~/ 8;
    expect(bytes, lessThan(AssetClient.maxUploadBytes));
    expect(mmss(kMaxVoiceNote), '15:00');
  });
}
