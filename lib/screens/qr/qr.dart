/// QR code — WhatsApp's Settings → QR code (decision 152). "My code"
/// is your profile link; "Scan code" reads someone else's and opens
/// their Contact info, with Message and Save contact.
library vartalap.screens.qr;

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:vartalap/screens/contact_info/contact_info.dart';
import 'package:vartalap/services/auth_service.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/username_link.dart';
import 'package:vartalap/widgets/avator.dart';

class QrScreen extends StatelessWidget {
  final AuthService authService;
  final ChatService chatService;

  /// Open on "Scan code" (from New chat) rather than "My code".
  final bool scan;

  const QrScreen({
    super.key,
    required this.authService,
    required this.chatService,
    this.scan = false,
  });

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        initialIndex: scan ? 1 : 0,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('QR code'),
            bottom: const TabBar(
              tabs: [Tab(text: 'My code'), Tab(text: 'Scan code')],
            ),
          ),
          body: TabBarView(
            // A swipe would start the camera half way; tabs only.
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _MyCode(authService: authService, chatService: chatService),
              _ScanCode(authService: authService, chatService: chatService),
            ],
          ),
        ),
      );
}

class _MyCode extends StatefulWidget {
  final AuthService authService;
  final ChatService chatService;
  const _MyCode({required this.authService, required this.chatService});

  @override
  State<_MyCode> createState() => _MyCodeState();
}

class _MyCodeState extends State<_MyCode> {
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    widget.chatService.ownAvatarUrl().then((url) {
      if (mounted) setState(() => _avatarUrl = url);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final auth = widget.authService;
    final username = auth.username;
    if (username == null) {
      return const Center(child: Text('Choose a username first'));
    }
    final key = auth.usernameKey;
    final name = auth.displayName ?? '@$username';
    return ListView(
      padding: const EdgeInsets.all(kSpaceLg),
      children: [
        Container(
          padding: const EdgeInsets.all(kSpaceLg),
          decoration: BoxDecoration(
            // Always light behind the modules: a QR on a dark surface
            // does not scan.
            color: Colors.white,
            borderRadius: BorderRadius.circular(kRadiusLg),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Avator(
                text: name,
                avatarUrl: _avatarUrl,
                width: kAvatarLg,
                height: kAvatarLg,
              ),
              const SizedBox(height: kSpaceSm),
              Text(name,
                  style: text.titleMedium?.copyWith(color: Colors.black87)),
              Text('@$username',
                  style: text.bodyMedium?.copyWith(color: Colors.black54)),
              const SizedBox(height: kSpaceMd),
              AspectRatio(
                aspectRatio: 1,
                child: QrImageView(
                  data: usernameLink(username, key: key),
                  backgroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: kSpaceMd),
        Text(
          key == null
              ? 'Anyone who scans this code can message you. It shares '
                  '@$username, never your number.'
              : 'Anyone who scans this code can message you: it carries '
                  'your username key. It never shares your number.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ScanCode extends StatefulWidget {
  final AuthService authService;
  final ChatService chatService;
  const _ScanCode({required this.authService, required this.chatService});

  @override
  State<_ScanCode> createState() => _ScanCodeState();
}

class _ScanCodeState extends State<_ScanCode> {
  PermissionStatus? _camera;

  /// The camera keeps reading the same code; act on it once until
  /// Contact info closes again.
  bool _busy = false;
  String? _lastBad;

  @override
  void initState() {
    super.initState();
    _askCamera();
  }

  Future<void> _askCamera() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _camera = status);
  }

  Future<void> _onScan(Code code) async {
    final raw = code.text;
    if (_busy || raw == null) return;
    if (parseUsernameLink(raw) == null) {
      if (raw == _lastBad) return;
      _lastBad = raw;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not a Vartalap QR code')),
      );
      return;
    }
    _busy = true;
    await openUsernameLink(
      context,
      link: raw,
      chatService: widget.chatService,
      authService: widget.authService,
    );
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    if (camera == null) return const Center(child: CircularProgressIndicator());
    if (!camera.isGranted) {
      final text = Theme.of(context).textTheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(kSpaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: kSpaceMd),
              Text(
                'Allow the camera to scan a Vartalap QR code.',
                textAlign: TextAlign.center,
                style: text.bodyLarge,
              ),
              const SizedBox(height: kSpaceMd),
              FilledButton(
                onPressed:
                    camera.isPermanentlyDenied ? openAppSettings : _askCamera,
                child: Text(camera.isPermanentlyDenied
                    ? 'Open settings'
                    : 'Allow camera'),
              ),
            ],
          ),
        ),
      );
    }
    return ReaderWidget(
      codeFormat: Format.qrCode,
      onScan: _onScan,
      showToggleCamera: false,
      // A screenshot of someone's code works too.
      showGallery: true,
    );
  }
}
