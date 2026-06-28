import 'dart:math';

int clampInt(num value, int minValue, int maxValue) {
  return max(minValue, min(maxValue, value.round()));
}

int calculateReadAccuracy({
  required int predictedShare,
  required int actualShare,
}) {
  return clampInt(100 - (predictedShare - actualShare).abs(), 0, 100);
}

int kFactor(int officialQuestionsAnswered) {
  if (officialQuestionsAnswered < 10) return 32;
  if (officialQuestionsAnswered < 50) return 24;
  if (officialQuestionsAnswered < 150) return 16;
  return 12;
}

int scoreDeltaForPercentile({
  required double percentile,
  required int officialQuestionsAnswered,
}) {
  final k = kFactor(officialQuestionsAnswered);
  final clamped = percentile.clamp(0.0, 1.0);
  return (k * ((clamped - 0.50) / 0.50)).round();
}
