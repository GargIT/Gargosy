// Adapted from Freegosy (MIT, © 2026 abduznik).
// Moved out of romm_models.dart (#233), which exports it.
class RomMConfig {
  final String baseUrl;
  final String username;
  final String password;
  final String? token;
  final String apiKey;
  final bool trustSelfSigned;

  RomMConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    this.token,
    this.apiKey = '',
    this.trustSelfSigned = false,
  });

  factory RomMConfig.fromJson(Map<String, dynamic> json) {
    return RomMConfig(
      baseUrl: json['baseUrl']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      token: json['token']?.toString(),
      apiKey: json['apiKey']?.toString() ?? '',
      trustSelfSigned: json['trustSelfSigned'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'username': username,
      'password': password,
      if (token != null) 'token': token,
      'apiKey': apiKey,
      'trustSelfSigned': trustSelfSigned,
    };
  }

  RomMConfig copyWith({
    String? baseUrl,
    String? username,
    String? password,
    String? token,
    String? apiKey,
    bool? trustSelfSigned,
  }) {
    return RomMConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      token: token ?? this.token,
      apiKey: apiKey ?? this.apiKey,
      trustSelfSigned: trustSelfSigned ?? this.trustSelfSigned,
    );
  }
}
