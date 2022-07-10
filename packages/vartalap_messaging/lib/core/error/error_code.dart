enum ErrorCode {
  undefinedToken,
  authRejected,
  unknown,
}

const _errorCodeWithDescription = {
  ErrorCode.unknown: MapEntry(-1, "Unkown"),
  // Local Error Starts with 1000
  ErrorCode.undefinedToken: MapEntry(1000, "Unauthorized, Token not defined"),

  // Server Error Between 0 - 999
  ErrorCode.authRejected:
      MapEntry(5, "Unauthentication, Server rejects Auth Token"),
};

const _authErrors = [
  ErrorCode.undefinedToken,
  ErrorCode.authRejected,
];

ErrorCode? errorCodeFromCode(int code) => _errorCodeWithDescription.keys
    .firstWhere((key) => _errorCodeWithDescription[key]!.key == code,
        orElse: () => ErrorCode.unknown);

extension ErrorCodeX on ErrorCode {
  String get message => _errorCodeWithDescription[this]!.value;

  int get code => _errorCodeWithDescription[this]!.key;

  bool get isAuthError => _authErrors.contains(this);
}
