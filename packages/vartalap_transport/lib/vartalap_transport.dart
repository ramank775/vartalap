/// Vartalap v3 transport layer.
///
/// Two adapters per `docs/SPIKE_B_SYNC.md` §7a:
/// - [WsTransport] for opaque chat-content envelopes (WS wire).
/// - [RestTransport] for server-state mutations (REST wire).
///
/// Both normalize their outcomes into [AckFrame] so the sync scheduler
/// handles them uniformly. Neither retries, rolls back, or dedups —
/// those concerns live in `vartalap_sync`.
///
/// [AuthClient] implements `AUTH_CONTRACT.md` — OTP, session refresh,
/// profile/contact reads, push topic registration, account delete,
/// phone rebind. It also implements [AuthTokenProvider] so transport
/// adapters can pull the current accesskey without a circular dep.
library vartalap_transport;

export 'src/ack.dart';
export 'src/auth_client.dart'
    show
        AuthClient,
        AuthClientException,
        ContactMatch,
        OtpSendResult,
        OtpVerifyResult,
        SessionRefreshResult;
export 'src/auth_token_provider.dart' show AuthTokenProvider;
export 'src/rest_transport.dart' show RestTransport, classifyHttpStatus;
export 'src/transport.dart'
    show FramedOp, OutboundFrame, Transport, TransportState;
export 'src/ws_transport.dart' show WsTransport;
