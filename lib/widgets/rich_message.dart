import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class RichMessage extends StatelessWidget {
  static final RegExp emojiRegex = RegExp(
    r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff])',
  );
  static final RegExp hyperlinkRegex = RegExp(
    r"^(http:\/\/www\.|https:\/\/www\.|http:\/\/|https:\/\/)?[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?$",
    caseSensitive: false,
  );
  static final RegExp emailRegex = RegExp(
    r"[a-zA-Z0-9-_.]+@[a-zA-Z0-9-_.]+",
    caseSensitive: false,
  );

  final TextStyle style;
  final String text;
  RichMessage(this.text, this.style);

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: generateMessageTextSpans(text),
        style: this.style,
      ),
    );
  }

  List<TextSpan> generateMessageTextSpans(String text) {
    List<TextSpan> spans = [];
    final TextStyle emojiStyle = style.copyWith(
      fontSize: (style.fontSize * 1.3),
      letterSpacing: 1,
    );

    final TextStyle hyperLinkStyle = style.copyWith(color: Colors.blue[700]);

    text.splitMapJoin(
      emojiRegex,
      onMatch: (m) {
        spans.add(
          TextSpan(
            text: m.group(0),
            style: emojiStyle,
          ),
        );
        return "";
      },
      onNonMatch: (s) {
        s.splitMapJoin(
          hyperlinkRegex,
          onMatch: (m) {
            spans.add(
              TextSpan(
                text: m.group(0),
                style: hyperLinkStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap = () => _launchUrl(
                        m.group(0),
                      ),
              ),
            );
            return "";
          },
          onNonMatch: (t) {
            t.splitMapJoin(emailRegex, onMatch: (m) {
              spans.add(
                TextSpan(
                  text: m.group(0),
                  style: hyperLinkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () =>
                        _launchUrl("mailto:${m.group(0)}?subject= &body= "),
                ),
              );
              return "";
            }, onNonMatch: (s) {
              spans.add(
                TextSpan(text: s),
              );
              return "";
            });

            return "";
          },
        );

        return "";
      },
    );
    return spans;
  }

  void _launchUrl(String link) async {
    link = link.toLowerCase();
    var uri = Uri.parse(link);
    if (!uri.hasScheme) {
      link = "http://$link";
    }
    if (await canLaunch(link)) await launch(link);
  }
}
