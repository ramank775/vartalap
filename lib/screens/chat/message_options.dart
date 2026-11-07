/// Decision 222's message features, the parts of the chat screen that are
/// dialogs and sheets: delete for me / for everyone, edit history, the
/// composer's timer and secure options, and opening a secure message.
library vartalap.screens.chat.message_options;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vartalap/services/chat_service.dart';
import 'package:vartalap_crypto/vartalap_crypto.dart'
    show SecretLocked, SecureUnlock;
import 'package:vartalap_store/vartalap_store.dart';

/// What the user picked in [confirmDeleteMessages].
enum DeleteChoice { forMe, forEveryone }

/// WhatsApp's "Delete message?": "Delete for everyone" only when
/// [forEveryone] (every selected message is the user's own and young
/// enough, decision 222), "Delete for me" always. Null on Cancel.
Future<DeleteChoice?> confirmDeleteMessages(
  BuildContext context, {
  required int count,
  required bool forEveryone,
}) =>
    showDialog<DeleteChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        content:
            Text(count == 1 ? 'Delete message?' : 'Delete $count messages?'),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (forEveryone)
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx).pop(DeleteChoice.forEveryone),
                  child: const Text('Delete for everyone'),
                ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(DeleteChoice.forMe),
                child: const Text('Delete for me'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );

/// Decision 222: an edited message's versions, newest first, each with
/// when it was written. Opened from the bubble's "edited".
Future<void> showEditHistory(
  BuildContext context,
  Future<List<MessageVersion>> versions,
) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String when(int ms) {
          final t = DateTime.fromMillisecondsSinceEpoch(ms);
          return '${MaterialLocalizations.of(ctx).formatMediumDate(t)}, '
              '${TimeOfDay.fromDateTime(t).format(ctx)}';
        }

        return SafeArea(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: FutureBuilder<List<MessageVersion>>(
              future: versions,
              builder: (ctx, snap) {
                final list = snap.data ?? const <MessageVersion>[];
                return ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text('Edit history',
                          style: Theme.of(ctx).textTheme.titleLarge),
                    ),
                    for (final (i, v) in list.indexed)
                      ListTile(
                        title: Text(v.body ?? ''),
                        subtitle: Text(
                          '${i == 0 ? 'Current' : i == list.length - 1 ? 'Original' : 'Earlier'}'
                          ' · ${when(v.atMs)}',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

/// The `vartalap/secure` channel (SecureScreen.kt): the phone's own
/// screen lock, and no screenshots while a secret shows. Without the
/// platform side (tests, desktop) there is no screen lock.
class SecureScreen {
  static const _channel = MethodChannel('vartalap/secure');

  static Future<T?> _call<T>(String method, [Object? argument]) async {
    try {
      return await _channel.invokeMethod<T>(method, argument);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Does this phone have a screen lock (PIN, pattern, password)?
  static Future<bool> lockSet() async => await _call<bool>('lockSet') ?? false;

  /// The system's fingerprint / face / PIN prompt; true once passed.
  static Future<bool> unlock() async =>
      await _call<bool>('unlock', 'Open secure message') ?? false;

  static Future<void> lockSettings() => _call<bool>('lockSettings');

  static Future<void> noCapture(bool on) => _call<void>('noCapture', on);
}

/// What the composer sends its next message with (decision 222): a timer
/// (seconds, 0 is Off), and whether it goes secure, opened with the
/// receiver's screen lock or, with [password], only with that, and
/// under what title (seen without unlocking, SYNC_PROTOCOL §20.4).
typedef ComposeOptions = ({
  int timerSec,
  bool secure,
  String? password,
  String? title,
});

const ComposeOptions kNoComposeOptions =
    (timerSec: 0, secure: false, password: null, title: null);

/// The shortest password a secure message takes.
const int kMinSecurePassword = 4;

/// One line for the composer: what [o] will do to the next message.
String composeOptionsText(ComposeOptions o) => [
      if (o.secure)
        '${o.title == null ? 'Secure' : 'Secure "${o.title}"'}: '
            '${o.password == null ? 'opens with their screen lock' : 'opens with your password'}',
      if (o.timerSec > 0)
        'Disappears ${kMessageTimers[o.timerSec]} after sending',
    ].join(' · ');

/// The composer's options sheet: secure (and how it opens) and the timer.
/// A phone with no screen lock offers the password way only (decision
/// 222): its user could not open their own copy otherwise. Null when
/// dismissed.
Future<ComposeOptions?> pickComposeOptions(
  BuildContext context,
  ComposeOptions current,
) async {
  final lockSet = await SecureScreen.lockSet();
  if (!context.mounted) return null;
  return showModalBottomSheet<ComposeOptions>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ComposeOptionsSheet(current: current, lockSet: lockSet),
  );
}

class _ComposeOptionsSheet extends StatefulWidget {
  final ComposeOptions current;
  final bool lockSet;
  const _ComposeOptionsSheet({required this.current, required this.lockSet});

  @override
  State<_ComposeOptionsSheet> createState() => _ComposeOptionsSheetState();
}

class _ComposeOptionsSheetState extends State<_ComposeOptionsSheet> {
  late int _timer = widget.current.timerSec;
  late bool _secure = widget.current.secure;
  late bool _byPassword = widget.current.password != null || !widget.lockSet;
  late final _password = TextEditingController(text: widget.current.password);
  late final _title = TextEditingController(text: widget.current.title);

  @override
  void dispose() {
    _password.dispose();
    _title.dispose();
    super.dispose();
  }

  Widget _radio(bool on, String title, String? subtitle, VoidCallback? onTap) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: on ? scheme.primary : null,
      ),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      enabled: onTap != null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockSet = widget.lockSet;
    final ready =
        !_secure || !_byPassword || _password.text.length >= kMinSecurePassword;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.lock_outline),
                title: const Text('Secure message'),
                subtitle: const Text('Hidden until they open it. Never '
                    'shown in notifications.'),
                value: _secure,
                onChanged: (v) => setState(() => _secure = v),
              ),
              if (_secure) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _title,
                    maxLength: kSecureTitleMax,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Title (optional)',
                      hintText: 'Netflix password, Bank OTP…',
                      helperText: 'Visible without unlocking',
                    ),
                  ),
                ),
                _radio(
                    !_byPassword,
                    'Opens with their screen lock',
                    lockSet
                        ? 'Fingerprint, face or PIN on their phone'
                        : 'Set a screen lock on this phone to use this',
                    lockSet ? () => setState(() => _byPassword = false) : null),
                _radio(
                    _byPassword,
                    'Opens with a password',
                    'Tell them the password another way, not in this chat. '
                        'A forgotten password cannot be recovered.',
                    () => setState(() => _byPassword = true)),
                if (_byPassword)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Password',
                          helperText:
                              'At least $kMinSecurePassword characters'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
              ],
              const ListTile(
                leading: Icon(Icons.timer_outlined),
                title: Text('Disappears after'),
                subtitle: Text('Gone from both phones this long after it '
                    'is sent'),
              ),
              for (final MapEntry(key: sec, value: label)
                  in kMessageTimers.entries)
                _radio(_timer == sec, label, null,
                    () => setState(() => _timer = sec)),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: ready
                          ? () => Navigator.of(context).pop((
                                timerSec: _timer,
                                secure: _secure,
                                password: _secure && _byPassword
                                    ? _password.text
                                    : null,
                                title: _secure &&
                                        secureTitle(_title.text).isNotEmpty
                                    ? secureTitle(_title.text)
                                    : null,
                              ))
                          : null,
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Decision 222: open the secure message [m]. Its own way first (the
/// screen lock, or the password), then the secret shows for 30 seconds
/// with screenshots blocked. A phone with no screen lock is asked to set
/// one.
Future<void> revealSecret(
    BuildContext context, ChatService chat, MessageRow m) async {
  final unlock = ChatService.secureUnlock(m);
  if (unlock == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Update Vartalap to open this secure message')));
    return;
  }
  String? secret;
  if (unlock == SecureUnlock.screenLock) {
    if (!await SecureScreen.lockSet()) {
      if (context.mounted) await _askForScreenLock(context);
      return;
    }
    if (!await SecureScreen.unlock()) return;
    secret = await chat.openSecure(m);
  } else {
    if (!context.mounted) return;
    secret = await showDialog<String>(
        context: context, builder: (_) => _PasswordDialog(chat: chat, m: m));
  }
  if (secret == null || !context.mounted) return;
  await showDialog<void>(
      context: context, builder: (_) => _SecretView(secret: secret!));
}

Future<void> _askForScreenLock(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Set a screen lock'),
      content: const Text('Secure messages open with this phone\'s screen '
          'lock: fingerprint, face or PIN. This phone has none yet.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now')),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open settings')),
      ],
    ),
  );
  if (open == true) await SecureScreen.lockSettings();
}

class _PasswordDialog extends StatefulWidget {
  final ChatService chat;
  final MessageRow m;
  const _PasswordDialog({required this.chat, required this.m});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final secret =
          await widget.chat.openSecure(widget.m, password: _password.text);
      if (mounted) Navigator.of(context).pop(secret);
    } on SecretLocked {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Wrong password';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Enter the password'),
        content: TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          enabled: !_busy,
          decoration: InputDecoration(
            labelText: 'Password',
            errorText: _error,
            helperText: 'The one the sender told you',
          ),
          onSubmitted: (_) => _open(),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _busy ? null : _open,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Open'),
          ),
        ],
      );
}

/// How long a secret stays on screen, and in the clipboard once copied.
const Duration kSecretShown = Duration(seconds: 30);
const Duration kSecretCopied = Duration(seconds: 60);

class _SecretView extends StatefulWidget {
  final String secret;
  const _SecretView({required this.secret});

  @override
  State<_SecretView> createState() => _SecretViewState();
}

class _SecretViewState extends State<_SecretView> {
  late final Timer _ticker;
  int _left = kSecretShown.inSeconds;

  @override
  void initState() {
    super.initState();
    SecureScreen.noCapture(true);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (--_left <= 0) {
        Navigator.of(context).pop();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    SecureScreen.noCapture(false);
    super.dispose();
  }

  void _copy() {
    final secret = widget.secret;
    Clipboard.setData(ClipboardData(text: secret));
    // ponytail: a Dart timer, so it fires only while the app runs; an
    // app frozen in the background leaves the copy until it is back.
    Timer(kSecretCopied, () async {
      try {
        final now = await Clipboard.getData(Clipboard.kTextPlain);
        // Unreadable (in the background): clear it anyway.
        if (now == null || now.text == secret) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      } catch (_) {/* no clipboard (tests) */}
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Copied. Cleared from the clipboard in a minute.')));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.lock_open_outlined),
          SizedBox(width: 8),
          Text('Secure message'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.secret, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('Hides in $_left s',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(onPressed: _copy, child: const Text('Copy')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
}
