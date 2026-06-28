import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'models.dart';
import 'scoring.dart';

const _fallbackOptions = [
  RtwOption(id: 'yes', label: 'Yes'),
  RtwOption(id: 'no', label: 'No'),
];

RtwQuestion questionFromFirestore(
  String id,
  Map<String, dynamic> data, {
  Map<String, dynamic>? resultData,
}) {
  final dailyKey =
      _stringValue(data['dailyKey']) ??
      _stringValue(resultData?['dailyKey']) ??
      _dailyKeyFromId(id);
  final options = _optionsFromValue(data['options'] ?? resultData?['options']);
  final worldShares = _intMapFromValue(
    resultData?['optionPcts'] ?? data['worldShares'] ?? data['optionPcts'],
  );
  final typeValue = _stringValue(data['type'] ?? resultData?['type']);
  return RtwQuestion(
    id: id,
    dailyKey: dailyKey,
    dateLabel: _dateLabel(
      dailyKey,
      data['publishAt'] ?? resultData?['closedAt'],
    ),
    category:
        (_stringValue(data['category'] ?? resultData?['category']) ?? 'GENERAL')
            .toUpperCase(),
    prompt: _stringValue(data['prompt'] ?? resultData?['prompt']) ?? '',
    options: options,
    worldShares: worldShares,
    type: typeValue == 'choice' || options.length > 2
        ? QuestionType.choice
        : QuestionType.binary,
    totalAnswers: _intValue(
      data['totalAnswers'] ?? resultData?['totalAnswers'],
    ),
  );
}

RtwQuestion questionFromDailyResult(String id, Map<String, dynamic> data) {
  return questionFromFirestore(id, data, resultData: data);
}

HistoryEntry historyEntryFromDailyResult({
  required String questionId,
  required Map<String, dynamic> resultData,
  Map<String, dynamic>? answerData,
  Map<String, dynamic>? scoreData,
}) {
  final question = questionFromDailyResult(questionId, resultData);
  final selectedOptionId = _stringValue(answerData?['selectedOptionId']);
  final prediction = _nullableIntValue(answerData?['predictedShare']);
  final actualShare = selectedOptionId == null
      ? null
      : question.worldShareFor(selectedOptionId);
  final calculatedAccuracy = selectedOptionId != null && prediction != null
      ? calculateReadAccuracy(
          predictedShare: prediction,
          actualShare: actualShare ?? 0,
        )
      : null;
  final readAccuracy =
      _nullableIntValue(scoreData?['readAccuracy']) ??
      _nullableIntValue(answerData?['readAccuracy']) ??
      calculatedAccuracy;
  final official = _boolValue(answerData?['official']) ?? true;

  return HistoryEntry(
    question: question,
    status: selectedOptionId == null
        ? HistoryStatus.skipped
        : official
        ? HistoryStatus.scored
        : HistoryStatus.revealed,
    selectedOptionId: selectedOptionId,
    prediction: prediction,
    readAccuracy: readAccuracy,
    readScoreDelta:
        _nullableIntValue(scoreData?['readScoreDelta']) ??
        _nullableIntValue(answerData?['readScoreDelta']),
    dailyPercentile:
        _nullableDoubleValue(scoreData?['dailyPercentile']) ??
        _nullableDoubleValue(answerData?['dailyPercentile']),
    officialCountedTowardScore:
        _boolValue(scoreData?['countedTowardScore']) ??
        _boolValue(answerData?['countedTowardScore']) ??
        false,
    played: !official && selectedOptionId != null,
  );
}

CategoryInsight categoryInsightFromStat(
  String id,
  Map<String, dynamic> data, {
  required bool best,
}) {
  return CategoryInsight(
    name: _displayCategory(_stringValue(data['category']) ?? id),
    score:
        _nullableIntValue(data['smoothedCategoryScore']) ??
        _nullableIntValue(data['averageReadAccuracy']) ??
        0,
    best: best,
  );
}

FriendRow friendFromLeaderboardRow(
  String uid,
  Map<String, dynamic> data, {
  required String currentUid,
}) {
  return FriendRow(
    uid: uid,
    name: _stringValue(data['displayName'])?.trim().isNotEmpty == true
        ? _stringValue(data['displayName'])!.trim()
        : uid == currentUid
        ? 'You'
        : 'Reader',
    score: _intValue(data['readScore'], fallback: 1500),
    me: uid == currentUid,
    answersShared: _boolValue(data['answersShared']) ?? false,
  );
}

String scorePercentileLabel(num? percentile) {
  if (percentile == null) return 'Keep reading the world';
  final top = (100 - percentile).clamp(1, 99).round();
  return 'Top $top% worldwide';
}

String formattedReadScore(int score) {
  return NumberFormat.decimalPattern('en_US').format(score);
}

String answeredCountLabel(int count) {
  return 'Across ${NumberFormat.decimalPattern('en_US').format(count)} '
      '${count == 1 ? 'question' : 'questions'} answered.';
}

String _dailyKeyFromId(String id) {
  final match = RegExp(r'^\d{4}-\d{2}-\d{2}').firstMatch(id);
  return match?.group(0) ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
}

String _dateLabel(String dailyKey, Object? timestampValue) {
  DateTime? date;
  if (dailyKey.length == 10) {
    date = DateTime.tryParse(dailyKey);
  }
  date ??= switch (timestampValue) {
    Timestamp value => value.toDate(),
    DateTime value => value,
    String value => DateTime.tryParse(value),
    _ => null,
  };
  if (date == null) return dailyKey.toUpperCase();
  return DateFormat('MMM d', 'en_US').format(date).toUpperCase();
}

List<RtwOption> _optionsFromValue(Object? value) {
  if (value is! Iterable) return _fallbackOptions;
  final options = value
      .map((raw) {
        if (raw is Map) {
          final data = Map<String, dynamic>.from(raw);
          final id = _stringValue(data['id']);
          final label = _stringValue(data['label']);
          if (id != null && label != null) {
            return RtwOption(id: id, label: label);
          }
        }
        if (raw is String && raw.trim().isNotEmpty) {
          final id = raw.trim().toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9]+'),
            '-',
          );
          return RtwOption(id: id, label: raw.trim());
        }
        return null;
      })
      .whereType<RtwOption>()
      .toList();
  return options.length >= 2 ? options : _fallbackOptions;
}

Map<String, int> _intMapFromValue(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(
    value,
  ).map((key, raw) => MapEntry(key, _intValue(raw)));
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int _intValue(Object? value, {int fallback = 0}) {
  return _nullableIntValue(value) ?? fallback;
}

int? _nullableIntValue(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _nullableDoubleValue(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

bool? _boolValue(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value == 'true') return true;
    if (value == 'false') return false;
  }
  return null;
}

String _displayCategory(String value) {
  final words = value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  return words
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}
