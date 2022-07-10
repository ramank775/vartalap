import 'package:vartalap_messaging/core/http/http_client.dart';

class BaseApi {
  BaseApi(this.client);

  String version = 'v1.0';
  String baseUrl = '';
  String endpoint({String? path}) =>
      "$version/$baseUrl${path == null ? '' : '/$path'}";

  final HttpClient client;
}
