import 'package:url_launcher/url_launcher.dart' as launcher;

launchUrl(String link) async {
  var uri = Uri.tryParse(link);
  if (uri == null) return;
  if (!uri.hasScheme) {
    uri = Uri.http(link, '');
  }
  if (await launcher.canLaunchUrl(uri)) await launcher.launchUrl(uri);
}
