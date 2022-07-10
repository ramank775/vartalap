import 'package:vartalap_messaging/core/api/asset.dart';
import 'package:vartalap_messaging/core/api/contact_book.dart';
import 'package:vartalap_messaging/core/api/group.dart';
import 'package:vartalap_messaging/core/api/message.dart';
import 'package:vartalap_messaging/core/api/user.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';
import 'package:vartalap_messaging/core/http/token_manager.dart';

class ApiClient {
  ApiClient({
    HttpClient? client,
    HttpClientOptions? options,
    TokenManager? tokenManger,
  }) : _client = client ??
            HttpClient(
              tokenManager: tokenManger,
              options: options,
            );

  final HttpClient _client;

  UserApi? _user;
  UserApi get user => _user ??= UserApi(_client);

  MessageApi? _message;
  MessageApi get message => _message ??= MessageApi(_client);

  GroupApi? _group;
  GroupApi get group => _group ??= GroupApi(_client);

  AssetApi? _asset;
  AssetApi get asset => _asset ??= AssetApi(_client);

  ContactBookApi? _contactbook;
  ContactBookApi get contactbook => _contactbook ??= ContactBookApi(_client);
}
