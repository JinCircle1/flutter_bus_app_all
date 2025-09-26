enum ErrorType { network, location, authentication, audio, unknown }

class AppError {
  final ErrorType type;
  final String message;
  final String? details;

  AppError({required this.type, required this.message, this.details});

  factory AppError.network(String message, [String? details]) {
    return AppError(
      type: ErrorType.network,
      message: message,
      details: details,
    );
  }

  factory AppError.location(String message, [String? details]) {
    return AppError(
      type: ErrorType.location,
      message: message,
      details: details,
    );
  }

  factory AppError.authentication(String message, [String? details]) {
    return AppError(
      type: ErrorType.authentication,
      message: message,
      details: details,
    );
  }

  factory AppError.audio(String message, [String? details]) {
    return AppError(type: ErrorType.audio, message: message, details: details);
  }

  factory AppError.unknown(String message, [String? details]) {
    return AppError(
      type: ErrorType.unknown,
      message: message,
      details: details,
    );
  }

  @override
  String toString() {
    return details != null ? '$message: $details' : message;
  }
}
