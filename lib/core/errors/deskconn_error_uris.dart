class DeskconnErrorUris {
  const DeskconnErrorUris._();

  static const userExists = 'io.xconn.error.user_exists';
  static const userNotFound = 'io.xconn.error.user_not_found';
  static const deviceExists = 'io.xconn.error.device_exists';
  static const deviceNotFound = 'io.xconn.error.device_not_found';
  static const userOtpInvalid = 'io.xconn.error.user_otp_invalid';
  static const userOtpCooldown = 'io.xconn.error.user_otp_cooldown';
  static const userOtpLimitExceeded = 'io.xconn.error.user_otp_limit_exceeded';
  static const userOtpTooManyAttempts = 'io.xconn.error.user_otp_too_many_attempts';
  static const userAlreadyVerified = 'io.xconn.error.user_already_verified';
  static const userNotVerified = 'io.xconn.error.user_not_verified';
  static const desktopExists = 'io.xconn.error.desktop_exists';
  static const desktopNotFound = 'io.xconn.error.desktop_not_found';
  static const organizationNotFound = 'io.xconn.error.organization_not_found';
  static const userNotAuthorized = 'io.xconn.error.user_not_authorized';
  static const userAlreadyMember = 'io.xconn.error.user_already_member';
  static const invitationAlreadySent = 'io.xconn.error.invitation_already_sent';
  static const invitationInvalid = 'io.xconn.error.invitation_invalid';
  static const invitationExpired = 'io.xconn.error.invitation_expired';
  static const invitationNotFound = 'io.xconn.error.invitation_not_found';
  static const internalError = 'io.xconn.error.internal_error';
  static const authenticationFailed = 'wamp.error.authentication_failed';
  static const principalExists = 'io.xconn.error.principal_exists';
  static const notFound = 'io.xconn.error.not_found';
  static const appVersionExists = 'io.xconn.error.app_version_exists';
  static const desktopAccessNotFound = 'io.xconn.error.desktop_access_not_found';

  static const values = [
    userExists,
    userNotFound,
    deviceExists,
    deviceNotFound,
    userOtpInvalid,
    userOtpCooldown,
    userOtpLimitExceeded,
    userOtpTooManyAttempts,
    userAlreadyVerified,
    userNotVerified,
    desktopExists,
    desktopNotFound,
    organizationNotFound,
    userNotAuthorized,
    userAlreadyMember,
    invitationAlreadySent,
    invitationInvalid,
    invitationExpired,
    invitationNotFound,
    internalError,
    authenticationFailed,
    principalExists,
    notFound,
    appVersionExists,
    desktopAccessNotFound,
  ];
}
