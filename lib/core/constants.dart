class DeskconnConfig {
  static const String quicAddr = "api.deskconn.com:8081";
  static const String realm = "io.xconn.deskconn";

  static const String serviceAuthId = "deskconn-web-app";

  // Most session.call() sites had no timeout at all — a peer that looks
  // "connected" but stopped responding (a common WebRTC/mobile-network
  // failure mode) left the caller awaiting forever with no way out.
  static const Duration callTimeout = Duration(seconds: 10);
}
