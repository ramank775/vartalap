import 'dart:async';

import 'package:vartalap_messaging/core/api/api_client.dart';
import 'package:vartalap_messaging/core/api/response.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/http/token.dart';
import 'package:vartalap_messaging/core/http/token_manager.dart';
import 'package:vartalap_messaging/core/models/channel.dart';
import 'package:vartalap_messaging/core/models/credentail.dart';
import 'package:vartalap_messaging/core/models/event.dart';
import 'package:vartalap_messaging/core/platform_detector/platform_detector.dart';
import 'package:vartalap_messaging/core/ws/websocket.dart';
import 'package:vartalap_messaging/version.dart';

const _defaultBaseURL = "https://vartalapapp.one9x.com";
const _defaultWSURL = "https://vartalapapp.one9x.com";
String _defaultUserAgent =
    "vartalap-messaging-dart-client-${CurrentPlatform.name}/$PACKAGE_VERSION";

class VartalapChatClient {
  VartalapChatClient({
    required String apiKey,
    required TokenManager tokenManager,
    String? apiBaseUrl,
    String? wsUrl,
    connectTimeout = const Duration(seconds: 60),
    receiveTimeout = const Duration(seconds: 60),
    pingInterval = const Duration(seconds: 60),
    String? userAgent,
    ApiClient? apiClient,
    Websocket? ws,
  }) {
    _tokenManager = tokenManager;
    _apiClient = apiClient ??
        ApiClient(
          apiKey,
          tokenManger: tokenManager,
          options: HttpClientOptions(
            baseUrl: apiBaseUrl ?? _defaultBaseURL,
            userAgent: userAgent ?? _defaultUserAgent,
            connectTimeout: connectTimeout,
            receiveTimeout: receiveTimeout,
          ),
        );
    _ws = ws ??
        Websocket(
          url: wsUrl ?? _defaultWSURL,
          tokenManager: tokenManager,
          pingInterval: pingInterval,
        );
    _wsStreamSub = _ws.messageStream.listen((msg) => _controller.sink.add(msg));
  }

  late final ApiClient _apiClient;
  late final Websocket _ws;
  late final TokenManager _tokenManager;
  late StreamSubscription<RemoteMessage> _wsStreamSub;

  final StreamController<RemoteMessage> _controller =
      StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get eventStream =>
      _controller.stream.asBroadcastStream();

  Future<String?> getLoggedInUser() async {
    final tkn = await _tokenManager.fetchActiveToken();
    return tkn?.userId;
  }

  Future<LoginResponse> login(Credential creds) async {
    final resp = await _apiClient.auth.login(creds);
    final token = Token(userId: resp.userId, accesskey: resp.accessKey);
    await _tokenManager.setToken(token);
    return resp;
  }

  Future<ProfileResponse> fetchProfile(String userId) async {
    return await _apiClient.user.get(userId);
  }

  Future<CreateChannelResponse> createChannel(ChannelPayload channel) async {
    return await _apiClient.channel.create(channel);
  }

  Future<ChannelsResponse> queryChannels() async {
    return await _apiClient.channel.getAll();
  }

  Future<ChannelResponse> getChannelInfo(String channelId) async {
    return await _apiClient.channel.getInfo(channelId);
  }

  Future<void> addChannelMembers(
    String channelId,
    List<String> memberIds,
  ) async {
    await _apiClient.channel.addMembers(channelId, memberIds);
  }

  Future<void> removeChannelMember(
    String channelId,
    String member,
  ) async {
    await _apiClient.channel.removeMember(channelId, member);
  }

  Future<void> sendMessage(
    List<RemoteMessage> messages, {
    bool sync = false,
    bool ack = true,
  }) async {
    if (sync) {
      final acks = await _apiClient.message.send(messages, ack: ack);
      for (var ack in acks) {
        _controller.sink.add(ack);
      }
    }
    for (var msg in messages) {
      await _ws.send(msg);
    }
  }

  Future<List<RemoteMessage>> syncMessages({
    bool stream = false,
  }) async {
    final resp = await _apiClient.message.fetch();
    if (stream) {
      for (var msg in resp.items) {
        _controller.sink.add(msg);
      }
      return [];
    }
    return resp.items;
  }

  Future<List<String>> syncContactBook(List<String> contacts) async {
    final resp = await _apiClient.contactbook.sync(contacts);
    return resp.available.toList(growable: false);
  }

  Future<AssetPreSignedUrlResponse> getUploadUrl(
    String ext,
    String category,
  ) async {
    return await _apiClient.asset.uploadUrl(ext, category);
  }

  Future<AssetPreSignedUrlResponse> getDownloadUrl(String assetId) async {
    return await _apiClient.asset.downloadUrl(assetId);
  }

  Future<void> markAssetAsUploaded(String assetId) async {
    await _apiClient.asset.markAssetAsUploaded(assetId);
  }

  Future<void> close() async {
    await _wsStreamSub.cancel();
  }
}
