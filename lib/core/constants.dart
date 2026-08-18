class DeskconnConfig {
  static const String quicAddr = "api.deskconn.com:8081";
  static const String realm = "io.xconn.deskconn";

  static const String serviceAuthId = "deskconn-web-app";

  // Most session.call() sites had no timeout at all — a peer that looks
  // "connected" but stopped responding (a common WebRTC/mobile-network
  // failure mode) left the caller awaiting forever with no way out.
  static const Duration callTimeout = Duration(seconds: 10);
}

class DeskconnProcedures {
  static const String accountCreate = 'io.xconn.deskconn.account.create';
  static const String accountDelete = 'io.xconn.deskconn.account.delete';
  static const String accountGet = 'io.xconn.deskconn.account.get';
  static const String accountPasswordForget = 'io.xconn.deskconn.account.password.forget';
  static const String accountPasswordReset = 'io.xconn.deskconn.account.password.reset';
  static const String accountUpdate = 'io.xconn.deskconn.account.update';
  static const String accountVerify = 'io.xconn.deskconn.account.verify';
  static const String accountOtpResend = 'io.xconn.deskconn.account.otp.resend';

  static const String desktopList = 'io.xconn.deskconn.desktop.list';
  static const String deviceCreate = 'io.xconn.deskconn.device.create';
  static const String deviceDelete = 'io.xconn.deskconn.device.delete';

  static const String deskconndAudioIsMuted = 'io.xconn.deskconn.deskconnd.audio.ismuted';
  static const String deskconndAudioToggleMute = 'io.xconn.deskconn.deskconnd.audio.togglemute';
  static const String deskconndFileBrowse = 'io.xconn.deskconn.deskconnd.file.browse';
  static const String deskconndFileCopy = 'io.xconn.deskconn.deskconnd.file.copy';
  static const String deskconndFileDelete = 'io.xconn.deskconn.deskconnd.file.delete';
  static const String deskconndFileDownload = 'io.xconn.deskconn.deskconnd.file.download';
  static const String deskconndFileRename = 'io.xconn.deskconn.deskconnd.file.rename';
  static const String deskconndFileUpload = 'io.xconn.deskconn.deskconnd.file.upload';
  static const String deskconndIndexQuery = 'io.xconn.deskconn.deskconnd.index.query';
  static const String deskconndKeyExchange = 'io.xconn.deskconn.deskconnd.key.exchange';
  static const String deskconndMprisNext = 'io.xconn.deskconn.deskconnd.mpris.next';
  static const String deskconndMprisPlayers = 'io.xconn.deskconn.deskconnd.mpris.players';
  static const String deskconndMprisPlayPause = 'io.xconn.deskconn.deskconnd.mpris.playpause';
  static const String deskconndMprisPrevious = 'io.xconn.deskconn.deskconnd.mpris.previous';
  static const String deskconndScreenBrightnessGet = 'io.xconn.deskconn.deskconnd.screen.brightness.get';
  static const String deskconndScreenBrightnessSet = 'io.xconn.deskconn.deskconnd.screen.brightness.set';
  static const String deskconndScreenLock = 'io.xconn.deskconn.deskconnd.screen.lock';
  static const String deskconndScreenshot = 'io.xconn.deskconn.deskconnd.screenshot';
  static const String deskconndShell = 'io.xconn.deskconn.deskconnd.shell';
  static const String deskconndWallpaperChecksum = 'io.xconn.deskconn.deskconnd.wallpaper.checksum';
  static const String deskconndWallpaperGet = 'io.xconn.deskconn.deskconnd.wallpaper.get';

  static const String webrtcOffer = 'io.xconn.webrtc.offer';
  static const String webrtcAnswererOnCandidate = 'io.xconn.webrtc.answerer.on_candidate';
  static const String webrtcOffererOnCandidate = 'io.xconn.webrtc.offerer.on_candidate';
}
