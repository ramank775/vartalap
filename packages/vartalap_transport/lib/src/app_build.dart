import 'dart:async';

import 'package:http/http.dart' as http;

/// Decision 192: this app's build (the Android versionCode), sent to our
/// server as `x-app-build` on every request and on the socket upgrade,
/// and what the server answered. Below its minimum build it refuses us
/// with 426; below its latest it names the latest in `x-latest-app-build`.
class AppBuild {
  AppBuild(this.build);

  final int build;
  bool _upgradeRequired = false;
  int _latest = 0;
  final _changes = StreamController<void>.broadcast();

  /// The server refused this build: only the update screen is left.
  bool get upgradeRequired => _upgradeRequired;

  /// A newer build is out; this one still works.
  bool get updateAvailable => _latest > build;

  Stream<void> get changes => _changes.stream;

  Map<String, String> get headers => {'x-app-build': '$build'};

  /// Every answer from our server goes through here.
  void observe(int status, String? latestHeader) {
    final latest = int.tryParse(latestHeader ?? '') ?? 0;
    final required = _upgradeRequired || status == 426;
    if (latest == _latest && required == _upgradeRequired) return;
    _latest = latest;
    _upgradeRequired = required;
    _changes.add(null);
  }
}

/// Adds [AppBuild.headers] to requests for [apiHost] and reports their
/// answers. Anything else (presigned R2 links) passes untouched.
class AppBuildClient extends http.BaseClient {
  AppBuildClient(this.appBuild, this.apiHost, [http.Client? inner])
      : _inner = inner ?? http.Client();

  final AppBuild appBuild;
  final String apiHost;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.host != apiHost) return _inner.send(request);
    request.headers.addAll(appBuild.headers);
    final response = await _inner.send(request);
    appBuild.observe(
        response.statusCode, response.headers['x-latest-app-build']);
    return response;
  }

  @override
  void close() => _inner.close();
}
