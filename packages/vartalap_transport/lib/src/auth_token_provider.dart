/// Bridges transport ↔ auth without a circular dep.
///
/// [AuthClient] implements this and injects it into [WsTransport] and
/// [RestTransport]. Transport asks for a token at frame-time; it never
/// owns token lifecycle (refresh, rotation, secure storage).
abstract class AuthTokenProvider {
  /// Current valid accesskey, or null if the user isn't signed in.
  String? get currentAccesskey;

  /// The canonical user_id (9 hex chars) for the signed-in session.
  /// null if not signed in. Used by the transport only for logging /
  /// connection URL; the server derives the authoritative user_id from
  /// the accesskey (AUTH_CONTRACT §6).
  String? get currentUserId;

  /// Called by transport when it receives a 401 / AUTH_FAILURE. Should
  /// attempt a session refresh and return the new accesskey, or null
  /// if refresh fails (scheduler will surface the auth failure).
  Future<String?> refresh();
}
