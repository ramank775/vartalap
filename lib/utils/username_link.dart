/// The profile QR and link (decision 152): `vartalap://u/<username>`,
/// plus `?k=<key>` when the owner has a username key. It carries the
/// handle, never the number (AUTH_CONTRACT §2.5).
library vartalap.utils.username_link;

String usernameLink(String username, {String? key}) => Uri(
      scheme: 'vartalap',
      host: 'u',
      pathSegments: [username],
      queryParameters: key == null ? null : {'k': key},
    ).toString();

/// Null for anything that is not a profile link.
({String username, String? key})? parseUsernameLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'vartalap' ||
      uri.host != 'u' ||
      uri.pathSegments.length != 1 ||
      uri.pathSegments.single.isEmpty) {
    return null;
  }
  return (username: uri.pathSegments.single, key: uri.queryParameters['k']);
}
