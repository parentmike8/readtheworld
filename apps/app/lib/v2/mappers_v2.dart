import 'models_v2.dart';

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? _nullableIntValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

double? _nullableDoubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return null;
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value is String) return value;
  return fallback;
}

String? _nullableString(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.whereType<Object>().map((item) => item.toString()).toList();
  }
  return const [];
}

RtwRoom roomFromFirestore(String id, Map<String, dynamic> data) {
  return RtwRoom(
    id: id,
    name: _stringValue(data['name'], fallback: 'Room'),
    colorToken: _stringValue(data['color'], fallback: 'oklch(0.50 0.10 256)'),
    tier: RoomTierWire.parse(_nullableString(data['tier'])),
    cats: _stringList(data['cats']).isEmpty
        ? const ['All']
        : _stringList(data['cats']),
    customEnabled: data['customEnabled'] != false,
    memberCount: _intValue(data['memberCount'], fallback: 1),
    isWorld: data['isWorld'] == true,
    worldGoal: _intValue(data['worldGoal'], fallback: 5000),
    inviteCode: _nullableString(data['inviteCode']),
    createdBy: _stringValue(data['createdBy']),
    currentDailyKey: _nullableString(data['currentDailyKey']),
    lastClosedDailyKey: _nullableString(data['lastClosedDailyKey']),
  );
}

RtwRoomMember roomMemberFromFirestore(String uid, Map<String, dynamic> data) {
  return RtwRoomMember(
    uid: uid,
    displayName: _stringValue(data['displayName'], fallback: 'Reader'),
    role: _stringValue(data['role'], fallback: 'member'),
    revealMine: data['revealMine'] == true,
    roomScore: _intValue(data['roomScore'], fallback: 1500),
    streak: _intValue(data['streak']),
    questionsAnswered: _intValue(data['questionsAnswered']),
    lastDelta: _nullableIntValue(data['lastDelta']),
    lastScoredDailyKey: _nullableString(data['lastScoredDailyKey']),
    lastPlayedDailyKey: _nullableString(data['lastPlayedDailyKey']),
    revealSeenDailyKey: _nullableString(data['revealSeenDailyKey']),
    rank: _nullableIntValue(data['rank']),
  );
}

RoomDayQuestion roomDayQuestionFromData(Map<String, dynamic> data) {
  return RoomDayQuestion(
    qid: _stringValue(data['qid']),
    prompt: _stringValue(data['prompt']),
    optA: _stringValue(data['optA'], fallback: 'Yes'),
    optB: _stringValue(data['optB'], fallback: 'No'),
    tag: _stringValue(data['tag'], fallback: 'Everyday'),
    shape: _stringValue(data['shape'], fallback: 'TASTE'),
    custom: data['custom'] == true,
    authorUid: _nullableString(data['authorUid']),
    authorName: _nullableString(data['authorName']),
    pulled: data['pulled'] == true,
    threshold: _nullableIntValue(data['threshold']),
  );
}

RoomDay roomDayFromFirestore(String dailyKey, Map<String, dynamic> data) {
  final rawQuestions = data['questions'];
  final rawResults = data['results'];
  final rawCounts = data['answerCounts'];
  return RoomDay(
    dailyKey: dailyKey,
    status: _stringValue(data['status'], fallback: 'live'),
    questions: rawQuestions is List
        ? rawQuestions
              .whereType<Map>()
              .map(
                (raw) =>
                    roomDayQuestionFromData(Map<String, dynamic>.from(raw)),
              )
              .where((question) => question.qid.isNotEmpty)
              .toList()
        : const [],
    results: rawResults is List
        ? rawResults
              .whereType<Map>()
              .map(
                (raw) => RoomDayQuestionResult(
                  qid: _stringValue(raw['qid']),
                  answers: _intValue(raw['answers']),
                  aCount: _intValue(raw['aCount']),
                  bCount: _intValue(raw['bCount']),
                  aPct: _intValue(raw['aPct']),
                ),
              )
              .toList()
        : const [],
    answerCount: _intValue(data['answerCount']),
    answerCounts: rawCounts is Map
        ? rawCounts.map(
            (key, value) => MapEntry(key.toString(), _intValue(value)),
          )
        : const {},
    revealedQids: data['revealedQids'] is List
        ? (data['revealedQids'] as List)
              .map((value) => value.toString())
              .toList()
        : const [],
  );
}

RoomPick roomPickFromData(Map<String, dynamic> data) {
  return RoomPick(
    qid: _stringValue(data['qid']),
    side: _stringValue(data['side'], fallback: 'a'),
    prediction:
        _nullableIntValue(data['prediction']) ??
        _nullableIntValue(data['predictedShare']),
  );
}

RoomAnswer roomAnswerFromFirestore(Map<String, dynamic> data) {
  final rawPicks = data['picks'];
  final rawAccuracies = data['accuracies'];
  return RoomAnswer(
    picks: rawPicks is List
        ? rawPicks
              .whereType<Map>()
              .map((raw) => roomPickFromData(Map<String, dynamic>.from(raw)))
              .toList()
        : const [],
    answerOnly: data['answerOnly'] == true,
    scored: data['scored'] == true,
    scoreDelta: _nullableIntValue(data['scoreDelta']),
    avgAccuracy: _nullableDoubleValue(data['avgAccuracy']),
    accuracies: rawAccuracies is Map
        ? rawAccuracies.map(
            (key, value) => MapEntry(key.toString(), _intValue(value)),
          )
        : const {},
  );
}

QueueItem queueItemFromFirestore(String id, Map<String, dynamic> data) {
  return QueueItem(
    id: id,
    text: _stringValue(data['text']),
    optA: _stringValue(data['optA'], fallback: 'Yes'),
    optB: _stringValue(data['optB'], fallback: 'No'),
    authorUid: _stringValue(data['authorUid']),
    authorName: _stringValue(data['authorName'], fallback: 'A member'),
  );
}

RoomDayDetailRow roomDayDetailRowFromData(Map<String, dynamic> data) {
  final rawPicks = data['picks'];
  final rawAccuracies = data['accuracies'];
  return RoomDayDetailRow(
    uid: _stringValue(data['uid']),
    displayName: _stringValue(data['displayName'], fallback: 'Reader'),
    isMe: data['isMe'] == true,
    reveals: data['reveals'] == true,
    picks: rawPicks is List
        ? rawPicks
              .whereType<Map>()
              .map((raw) => roomPickFromData(Map<String, dynamic>.from(raw)))
              .toList()
        : const [],
    scoreDelta: _nullableIntValue(data['scoreDelta']),
    avgAccuracy: _nullableDoubleValue(data['avgAccuracy']),
    accuracies: rawAccuracies is Map
        ? rawAccuracies.map(
            (key, value) => MapEntry(key.toString(), _intValue(value)),
          )
        : const {},
  );
}

PartyQuestion partyQuestionFromData(Map<String, dynamic> data) {
  return PartyQuestion(
    qid: _stringValue(data['qid']),
    prompt: _stringValue(data['prompt']),
    optA: _stringValue(data['optA'], fallback: 'Yes'),
    optB: _stringValue(data['optB'], fallback: 'No'),
    tag: _stringValue(data['tag'], fallback: 'Everyday'),
    shape: _stringValue(data['shape'], fallback: 'TASTE'),
    tier: _stringValue(data['tier'], fallback: 'work-safe'),
  );
}
