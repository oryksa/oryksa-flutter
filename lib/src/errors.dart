/// Error returned by the ORYKSA API.
///
/// [code] is a stable machine code, for example `interaction_limit_reached`,
/// `rate_limited`, `plan_required` or `session_expired`.
class OryksaException implements Exception {
  /// Creates an error.
  const OryksaException(this.status, this.code, this.message, [this.extra = const {}]);

  /// HTTP status (0 when the request did not reach the server).
  final int status;

  /// Machine readable code.
  final String code;

  /// Human readable message (English).
  final String message;

  /// Any other fields the API returned with the error.
  final Map<String, dynamic> extra;

  @override
  String toString() => 'OryksaException($status, $code): $message';
}
