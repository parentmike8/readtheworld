enum QuestionType { binary, choice }

enum HistoryStatus { scored, skipped, revealed }

class RtwOption {
  const RtwOption({required this.id, required this.label});

  final String id;
  final String label;
}

class RtwQuestion {
  const RtwQuestion({
    required this.id,
    required this.dailyKey,
    required this.dateLabel,
    required this.category,
    required this.prompt,
    required this.options,
    required this.worldShares,
    this.type = QuestionType.binary,
    this.totalAnswers = 0,
    this.closeAt,
  });

  final String id;
  final String dailyKey;
  final String dateLabel;
  final String category;
  final String prompt;
  final List<RtwOption> options;
  final Map<String, int> worldShares;
  final QuestionType type;
  final int totalAnswers;
  final DateTime? closeAt;

  int worldShareFor(String optionId) => worldShares[optionId] ?? 0;
  RtwOption option(String optionId) => options.firstWhere(
    (option) => option.id == optionId,
    orElse: () => options.first,
  );
}

class HistoryEntry {
  const HistoryEntry({
    required this.question,
    required this.status,
    this.selectedOptionId,
    this.prediction,
    this.readAccuracy,
    this.readScoreDelta,
    this.dailyPercentile,
    this.officialCountedTowardScore,
    this.played = false,
    this.peeked = false,
  });

  final RtwQuestion question;
  final HistoryStatus status;
  final String? selectedOptionId;
  final int? prediction;
  final int? readAccuracy;
  final int? readScoreDelta;
  final double? dailyPercentile;
  final bool? officialCountedTowardScore;
  final bool played;
  final bool peeked;

  bool get hasAnswer => selectedOptionId != null && prediction != null;
  bool get countedTowardScore =>
      officialCountedTowardScore ??
      (status == HistoryStatus.scored && !played && !peeked);

  HistoryEntry copyWith({
    HistoryStatus? status,
    String? selectedOptionId,
    int? prediction,
    int? readAccuracy,
    int? readScoreDelta,
    double? dailyPercentile,
    bool? officialCountedTowardScore,
    bool? played,
    bool? peeked,
  }) {
    return HistoryEntry(
      question: question,
      status: status ?? this.status,
      selectedOptionId: selectedOptionId ?? this.selectedOptionId,
      prediction: prediction ?? this.prediction,
      readAccuracy: readAccuracy ?? this.readAccuracy,
      readScoreDelta: readScoreDelta ?? this.readScoreDelta,
      dailyPercentile: dailyPercentile ?? this.dailyPercentile,
      officialCountedTowardScore:
          officialCountedTowardScore ?? this.officialCountedTowardScore,
      played: played ?? this.played,
      peeked: peeked ?? this.peeked,
    );
  }
}

class CategoryInsight {
  const CategoryInsight({
    required this.name,
    required this.score,
    required this.best,
  });

  final String name;
  final int score;
  final bool best;
}

class FriendRow {
  const FriendRow({
    this.uid,
    required this.name,
    required this.score,
    this.me = false,
    this.answersShared = false,
  });

  final String? uid;
  final String name;
  final int score;
  final bool me;
  final bool answersShared;

  FriendRow copyWith({bool? answersShared}) {
    return FriendRow(
      uid: uid,
      name: name,
      score: score,
      me: me,
      answersShared: answersShared ?? this.answersShared,
    );
  }
}

class FriendAnswerComparison {
  const FriendAnswerComparison({
    required this.uid,
    required this.name,
    required this.selectedOptionId,
    required this.predictedShare,
    this.readAccuracy,
  });

  final String uid;
  final String name;
  final String selectedOptionId;
  final int predictedShare;
  final int? readAccuracy;
}
