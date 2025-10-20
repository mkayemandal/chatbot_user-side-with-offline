import 'package:uuid/uuid.dart';

class GuestSessionManager {
  static final GuestSessionManager _instance = GuestSessionManager._internal();
  factory GuestSessionManager() => _instance;
  GuestSessionManager._internal();

  late String sessionId;
  late String openId;

  void initialize() {
    sessionId = const Uuid().v4();
    openId = const Uuid().v4();
  }
}