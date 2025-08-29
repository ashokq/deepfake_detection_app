class InferenceResult {
  final String label; // "real" or "fake"
  final double score; // confidence 0..1

  InferenceResult({required this.label, required this.score});

  bool get isFake => label.toLowerCase().contains('fake');

  @override
  String toString() => '$label (${(score * 100).toStringAsFixed(1)}%)';
}
