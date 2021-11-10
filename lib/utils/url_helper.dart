import 'package:url_launcher/url_launcher.dart';

launchUrl(String link) async {
  link = link.toLowerCase();
  var uri = Uri.parse(link);
  if (!uri.hasScheme) {
    link = "http://$link";
  }
  if (await canLaunch(link)) await launch(link);
}
