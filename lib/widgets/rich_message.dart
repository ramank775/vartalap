import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vartalap/theme/theme.dart';
import 'package:vartalap/utils/url_helper.dart';

class RichMessage extends StatelessWidget {
  static final RegExp emojiRegex = RegExp(
    r'(\u00a9|\u00ae|[\u2000-\u3300]|\ud83c[\ud000-\udfff]|\ud83d[\ud000-\udfff]|\ud83e[\ud000-\udfff]|[\uf000-\uffff])',
  );
  static final RegExp hyperlinkRegex = RegExp(
    r"(http:\/\/www\.|https:\/\/www\.|http:\/\/|https:\/\/|ws:\/\/|wss:\/\/)?[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?",
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp emailRegex = RegExp(
    r"[a-zA-Z0-9-_.]+@[a-zA-Z0-9-_.]+",
    caseSensitive: false,
  );

  final TextStyle style;
  final String text;
  final bool selectable;
  RichMessage(this.text, this.style, {this.selectable = false});

  @override
  Widget build(BuildContext context) {
    final txtSpan = TextSpan(
      children: generateMessageTextSpans(text),
      style: this.style,
    );
    if (selectable) {
      return SelectableText.rich(txtSpan);
    }
    return RichText(text: txtSpan);
  }

  List<TextSpan> generateMessageTextSpans(String text) {
    List<TextSpan> spans = [];
    final TextStyle emojiStyle = style.copyWith(
      fontSize: (style.fontSize! * 1.5),
      letterSpacing: 0.5,
    );

    final TextStyle combinedEmojiStyle = emojiStyle.copyWith(
      fontSize: style.fontSize! * 1.7,
    );

    final TextStyle hyperLinkStyle =
        this.style.merge(VartalapTheme.theme.linkTitleStyle);
    String emojiString = "";

    text.splitMapJoin(
      emojiRegex,
      onMatch: (m) {
        emojiString += m.group(0)!;
        return "";
      },
      onNonMatch: (s) {
        if (s.isEmpty) {
          return "";
        } else if (emojiString.isNotEmpty) {
          spans.add(
            TextSpan(
              text: emojiString,
              style: emojiString.length > 1 ? combinedEmojiStyle : emojiStyle,
            ),
          );
          emojiString = "";
        }
        s.splitMapJoin(
          emailRegex,
          onMatch: (m) {
            spans.add(
              TextSpan(
                text: m.group(0),
                style: hyperLinkStyle,
                recognizer: TapGestureRecognizer()
                  ..onTap =
                      () => _launchUrl("mailto:${m.group(0)}?subject= &body= "),
              ),
            );

            return "";
          },
          onNonMatch: (t) {
            t.splitMapJoin(hyperlinkRegex, onMatch: (m) {
              spans.add(
                TextSpan(
                  text: m.group(0),
                  style: hyperLinkStyle,
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _launchUrl(
                          m.group(0)!,
                        ),
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
    if (emojiString.isNotEmpty) {
      spans.add(
        TextSpan(
          text: emojiString,
          style: emojiStyle,
        ),
      );
      emojiString = "";
    }
    return spans;
  }

  void _launchUrl(String link) async {
    await launchUrl(link);
  }
}
