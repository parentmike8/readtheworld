/// v2 rooms data models. Field semantics follow functions/src/index.ts
/// (v2 section) and docs/v2-implementation-spec.md §7.
library;

enum RoomTier { workSafe, normal, mature }

enum QuestionReaction { liked, disliked }

extension RoomTierWire on RoomTier {
  String get wire => switch (this) {
    RoomTier.workSafe => 'work-safe',
    RoomTier.normal => 'normal',
    RoomTier.mature => 'mature',
  };

  String get label => switch (this) {
    RoomTier.workSafe => 'Work-safe',
    RoomTier.normal => 'Everyday',
    RoomTier.mature => 'After Dark',
  };

  static RoomTier parse(String? value) => switch (value) {
    'work-safe' => RoomTier.workSafe,
    'mature' => RoomTier.mature,
    _ => RoomTier.normal,
  };

  /// Mirrors functions/src/rooms.ts tierAllowsQuestion: Everyday includes
  /// work-safe, but After Dark drops work-safe so the edgy game stays edgy.
  bool allowsQuestionTier(String questionTier) => switch (this) {
    RoomTier.workSafe => questionTier == 'work-safe',
    RoomTier.normal => questionTier != 'mature',
    RoomTier.mature => questionTier != 'work-safe',
  };
}

class RtwRoom {
  const RtwRoom({
    required this.id,
    required this.name,
    required this.colorToken,
    required this.tier,
    required this.cats,
    required this.customEnabled,
    required this.memberCount,
    required this.isWorld,
    this.worldGoal = 5000,
    this.inviteCode,
    this.createdBy = '',
    this.currentDailyKey,
    this.lastClosedDailyKey,
  });

  final String id;
  final String name;
  final String colorToken;
  final RoomTier tier;
  final List<String> cats;
  final bool customEnabled;
  final int memberCount;
  final bool isWorld;
  final int worldGoal;
  final String? inviteCode;
  final String createdBy;
  final String? currentDailyKey;
  final String? lastClosedDailyKey;

  bool get isSolo => !isWorld && memberCount <= 1;
  bool get isDuo => !isWorld && memberCount == 2;
  String get initial => name.isEmpty ? '?' : name.substring(0, 1);
}

class RtwRoomMember {
  const RtwRoomMember({
    required this.uid,
    required this.displayName,
    required this.role,
    required this.revealMine,
    required this.roomScore,
    required this.streak,
    required this.questionsAnswered,
    this.lastDelta,
    this.lastScoredDailyKey,
    this.lastPlayedDailyKey,
    this.revealSeenDailyKey,
    this.rank,
  });

  final String uid;
  final String displayName;
  final String role;
  final bool revealMine;
  final int roomScore;
  final int streak;
  final int questionsAnswered;
  final int? lastDelta;
  final String? lastScoredDailyKey;
  final String? lastPlayedDailyKey;
  final String? revealSeenDailyKey;

  /// Room standing written at day close (1 = top).
  final int? rank;

  bool get isCreator => role == 'creator';
}

class RoomNudgeStatus {
  const RoomNudgeStatus({
    required this.targetName,
    required this.nudgeCount,
    required this.alreadyNudged,
    required this.canNudge,
    required this.outgoingRemaining,
    this.blockReason,
  });

  final String targetName;
  final int nudgeCount;
  final bool alreadyNudged;
  final bool canNudge;
  final int outgoingRemaining;
  final String? blockReason;

  factory RoomNudgeStatus.fromData(Map<String, dynamic> data) {
    return RoomNudgeStatus(
      targetName: data['targetName']?.toString() ?? 'Reader',
      nudgeCount: (data['nudgeCount'] as num?)?.toInt() ?? 0,
      alreadyNudged: data['alreadyNudged'] == true,
      canNudge: data['canNudge'] == true,
      outgoingRemaining: (data['outgoingRemaining'] as num?)?.toInt() ?? 0,
      blockReason: data['blockReason']?.toString(),
    );
  }
}

class RoomDayQuestion {
  const RoomDayQuestion({
    required this.qid,
    required this.prompt,
    required this.optA,
    required this.optB,
    required this.tag,
    required this.shape,
    required this.custom,
    this.authorUid,
    this.authorName,
    this.pulled = false,
    this.threshold,
  });

  final String qid;
  final String prompt;
  final String optA;
  final String optB;
  final String tag;
  final String shape;
  final bool custom;
  final String? authorUid;
  final String? authorName;
  final bool pulled;
  final int? threshold;
}

class RoomDayQuestionResult {
  const RoomDayQuestionResult({
    required this.qid,
    required this.answers,
    required this.aCount,
    required this.bCount,
    required this.aPct,
  });

  final String qid;
  final int answers;
  final int aCount;
  final int bCount;
  final int aPct;
}

class RoomDay {
  const RoomDay({
    required this.dailyKey,
    required this.status,
    required this.questions,
    this.results = const [],
    this.answerCount = 0,
    this.answerCounts = const {},
    this.revealedQids = const [],
  });

  final String dailyKey;
  final String status;
  final List<RoomDayQuestion> questions;
  final List<RoomDayQuestionResult> results;
  final int answerCount;
  final Map<String, int> answerCounts;

  /// World only: questions that have crossed their threshold and revealed.
  /// They can no longer be answered, only viewed.
  final List<String> revealedQids;

  bool get isLive => status == 'live';
  bool get isClosed => status == 'closed';
  List<RoomDayQuestion> get activeQuestions =>
      questions.where((question) => !question.pulled).toList();

  /// Questions still open for answering (active and not yet revealed).
  List<RoomDayQuestion> get answerableQuestions => questions
      .where(
        (question) => !question.pulled && !revealedQids.contains(question.qid),
      )
      .toList();

  bool isRevealed(String qid) => revealedQids.contains(qid);

  RoomDayQuestionResult? resultFor(String qid) {
    for (final result in results) {
      if (result.qid == qid) return result;
    }
    return null;
  }
}

/// The caller's own locked answers for one room-day.
class RoomAnswer {
  const RoomAnswer({
    required this.picks,
    required this.answerOnly,
    this.scored = false,
    this.scoreDelta,
    this.avgAccuracy,
    this.accuracies = const {},
  });

  final List<RoomPick> picks;
  final bool answerOnly;
  final bool scored;
  final int? scoreDelta;
  final double? avgAccuracy;
  final Map<String, int> accuracies;

  RoomPick? pickFor(String qid) {
    for (final pick in picks) {
      if (pick.qid == qid) return pick;
    }
    return null;
  }
}

class RoomPick {
  const RoomPick({required this.qid, required this.side, this.prediction});

  final String qid;

  /// 'a' or 'b' — referencing the question's optA / optB.
  final String side;
  final int? prediction;
}

/// One row in the World leaderboard (how you read all of humanity versus
/// everyone you share a room with).
class WorldLeaderRow {
  const WorldLeaderRow({
    required this.rank,
    required this.uid,
    required this.displayName,
    required this.avatarColor,
    required this.readScore,
    required this.questionsScored,
  });

  final int rank;
  final String uid;
  final String displayName;
  final String avatarColor;
  final int readScore;
  final int questionsScored;
}

class QueueItem {
  const QueueItem({
    required this.id,
    required this.text,
    required this.optA,
    required this.optB,
    required this.authorUid,
    required this.authorName,
  });

  final String id;
  final String text;
  final String optA;
  final String optB;
  final String authorUid;
  final String authorName;
}

/// One card in the Today swipe deck. Intro cards announce a room block.
class TodayDeckCard {
  const TodayDeckCard.intro({
    required this.roomId,
    required this.roomName,
    required this.roomColorToken,
    required this.roomMembers,
    required this.roomTotal,
    required this.isWorld,
  }) : intro = true,
       question = null,
       indexInRoom = -1;

  const TodayDeckCard.question({
    required this.roomId,
    required this.roomName,
    required this.roomColorToken,
    required this.roomMembers,
    required this.roomTotal,
    required this.isWorld,
    required RoomDayQuestion this.question,
    required this.indexInRoom,
  }) : intro = false;

  final bool intro;
  final String roomId;
  final String roomName;
  final String roomColorToken;
  final int roomMembers;
  final int roomTotal;
  final bool isWorld;
  final RoomDayQuestion? question;
  final int indexInRoom;
}

/// Play-surface stage, mirroring the prototype's `play.stage` values.
enum PlayStage { pick, predict, reveal, answerSaved }

/// Per-member row in the closed-day detail (question leaderboard sheet).
class RoomDayDetailRow {
  const RoomDayDetailRow({
    required this.uid,
    required this.displayName,
    required this.isMe,
    required this.reveals,
    required this.picks,
    this.scoreDelta,
    this.avgAccuracy,
    this.accuracies = const {},
  });

  final String uid;
  final String displayName;
  final bool isMe;
  final bool reveals;
  final List<RoomPick> picks;
  final int? scoreDelta;
  final double? avgAccuracy;
  final Map<String, int> accuracies;
}

/// Party pool question fetched from the cloud bank (cached for offline).
class PartyQuestion {
  const PartyQuestion({
    required this.qid,
    required this.prompt,
    required this.optA,
    required this.optB,
    required this.tag,
    required this.shape,
    this.tier = 'work-safe',
  });

  final String qid;
  final String prompt;
  final String optA;
  final String optB;
  final String tag;
  final String shape;

  /// Bank tier wire value: 'work-safe' | 'normal' | 'mature'.
  final String tier;
}
