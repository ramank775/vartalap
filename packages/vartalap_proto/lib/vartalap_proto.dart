/// Generated protobuf bindings for the Vartalap v3 sync wire.
///
/// - Envelope, Ack, WsEnvelope etc. mirror `docs/proto/v3-envelope.proto`.
/// - ChatPayload, ChatPayloadType, Attachment, ForwardSource mirror
///   `docs/proto/v3-chat-payload.proto`. The server never imports these;
///   they are the reference client-to-client schema.
library vartalap_proto;

export 'src/generated/v3-envelope.pb.dart'
    show Envelope, Ack, WsEnvelope, EnvelopeBatch, AckBatch, WsError;
export 'src/generated/v3-envelope.pbenum.dart' show AckOutcome, WsType;
export 'src/generated/v3-chat-payload.pb.dart'
    show ChatPayload, Attachment, ForwardSource;
export 'src/generated/v3-chat-payload.pbenum.dart' show ChatPayloadType;
