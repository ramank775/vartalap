import 'package:vartalap_messaging/core/api/asset.dart';
import 'package:vartalap_messaging/core/api/auth.dart';
import 'package:vartalap_messaging/core/api/contact_book.dart';
import 'package:vartalap_messaging/core/api/channel.dart';
import 'package:vartalap_messaging/core/api/message.dart';
import 'package:vartalap_messaging/core/api/user.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/http/token_manager.dart';

class ApiClient {
  ApiClient(
    String apiKey, {
    required HttpClientOptions options,
    TokenManager? tokenManger,
  }) : _client = HttpClient(
          tokenManager: tokenManger,
          options: options,
          apiKey: apiKey,
        );

  final HttpClient _client;

  AuthApi? _authApi;
  AuthApi get auth => _authApi ??= AuthApi(_client);

  UserApi? _user;
  UserApi get user => _user ??= UserApi(_client);

  MessageApi? _message;
  MessageApi get message => _message ??= MessageApi(_client);

  ChannelApi? _channel;
  ChannelApi get channel => _channel ??= ChannelApi(_client);

  AssetApi? _asset;
  AssetApi get asset => _asset ??= AssetApi(_client);

  ContactBookApi? _contactbook;
  ContactBookApi get contactbook => _contactbook ??= ContactBookApi(_client);
}
