import 'pin.dart';

/// One person on this PC: a RomM user on a server, plus a name, colour and PIN.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.colorIndex,
    required this.serverUrl,
    required this.rommUserId,
    required this.rommUsername,
    required this.createdAt,
    this.hasAvatar = false,
    this.pin,
    this.trustSelfSigned = false,
  });

  final String id;
  final String name;
  final int colorIndex;
  final String serverUrl;
  final int rommUserId;
  final String rommUsername;
  final DateTime createdAt;
  final bool hasAvatar;
  final PinHash? pin;
  final bool trustSelfSigned;

  Profile copyWith({String? name, int? colorIndex, bool? hasAvatar, PinHash? pin, bool clearPin = false}) => Profile(
        id: id,
        name: name ?? this.name,
        colorIndex: colorIndex ?? this.colorIndex,
        serverUrl: serverUrl,
        rommUserId: rommUserId,
        rommUsername: rommUsername,
        createdAt: createdAt,
        hasAvatar: hasAvatar ?? this.hasAvatar,
        pin: clearPin ? null : (pin ?? this.pin),
        trustSelfSigned: trustSelfSigned,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorIndex': colorIndex,
        'serverUrl': serverUrl,
        'rommUserId': rommUserId,
        'rommUsername': rommUsername,
        'createdAt': createdAt.toIso8601String(),
        'hasAvatar': hasAvatar,
        if (pin != null) 'pin': pin!.toJson(),
        'trustSelfSigned': trustSelfSigned,
      };

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        name: json['name'] as String,
        colorIndex: json['colorIndex'] as int? ?? 0,
        serverUrl: json['serverUrl'] as String,
        rommUserId: json['rommUserId'] as int,
        rommUsername: json['rommUsername'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        hasAvatar: json['hasAvatar'] == true,
        pin: json['pin'] is Map<String, dynamic> ? PinHash.fromJson(json['pin'] as Map<String, dynamic>) : null,
        trustSelfSigned: json['trustSelfSigned'] == true,
      );
}
