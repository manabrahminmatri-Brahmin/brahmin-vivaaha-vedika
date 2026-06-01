class RequestUiContract {
  RequestUiContract._();

  // Action labels
  static const String accept = 'Accept';
  static const String decline = 'Decline';
  static const String withdraw = 'Withdraw';
  static const String reminder = 'Reminder';
  static const String sendAgain = 'Send Again';

  // Progress labels
  static const String withdrawing = 'Withdrawing...';
  static const String sending = 'Sending...';

  // Status labels
  static const String accepted = 'Accepted';
  static const String declined = 'Declined';
  static const String pendingAwaitingApproval =
      'Request Sent — Awaiting Owner Approval';
  static const String accessGrantedByOwner = 'Access Granted by Profile Owner';
  static const String requestDeclinedByOwner = 'Request Declined by Profile Owner';
  static const String premiumMembersOnly = 'Premium Members Only';

  // Snackbar / toast text
  static const String reminderSent = 'Reminder sent successfully';
  static const String reminderPendingOnly =
      'Reminder is available only for pending requests';
  static const String respondFailed = 'Failed to respond';
  static const String withdrawFailed = 'Failed to withdraw request';
  static const String reminderFailed = 'Failed to send reminder';
  static const String sendRequestFailed = 'Failed to send request';
  static const String photoRequestSent =
      'Photo request sent. You will be notified when they respond.';
}
