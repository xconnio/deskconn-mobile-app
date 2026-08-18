class OperationResult {
  final String? error;

  const OperationResult.success() : error = null;
  const OperationResult.failure(this.error);

  bool get isSuccess => error == null;
}
