import 'package:meta/meta.dart';
import 'package:vartalap_messaging/core/http/http_client.dart';

abstract class BaseApi {
  BaseApi(this.client, this._baseUrl);
  final String _baseUrl;

  @protected
  String version = 'v1.0';

  @protected
  String endpoint({String? path}) =>
      "$version/$_baseUrl${path == null ? '' : '/$path'}";
  @protected
  final HttpClient client;
}
