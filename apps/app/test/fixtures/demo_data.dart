import 'package:read_the_world/models.dart';

const yesNo = [
  RtwOption(id: 'yes', label: 'Yes'),
  RtwOption(id: 'no', label: 'No'),
];

final todayQuestion = RtwQuestion(
  id: '2026-06-26-philosophy-death-date',
  dailyKey: '2026-06-26',
  dateLabel: 'JUN 26',
  category: 'PHILOSOPHY',
  prompt: "Would you want to know the exact date you'll die?",
  options: yesNo,
  worldShares: const {'yes': 38, 'no': 62},
  totalAnswers: 185053,
);

final yesterdayQuestion = RtwQuestion(
  id: '2026-06-25-technology-ai-labels',
  dailyKey: '2026-06-25',
  dateLabel: 'JUN 25',
  category: 'TECHNOLOGY',
  prompt: 'Should AI-generated content always be labelled?',
  options: yesNo,
  worldShares: const {'yes': 84, 'no': 16},
  totalAnswers: 1400000,
);

const _monthsAbbr = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

class _HistorySeed {
  const _HistorySeed({
    required this.category,
    required this.prompt,
    required this.worldYes,
  });

  final String category;
  final String prompt;
  final int worldYes;
}

const _historySeeds = [
  _HistorySeed(
    category: 'TECHNOLOGY',
    prompt: 'Should AI-generated content always be labelled?',
    worldYes: 84,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Is it rude to keep your phone on the table during dinner?',
    worldYes: 62,
  ),
  _HistorySeed(
    category: 'SCIENCE',
    prompt: 'Will fusion power reach the grid within 20 years?',
    worldYes: 54,
  ),
  _HistorySeed(
    category: 'MONEY',
    prompt: 'Would you take a 20% pay cut for a four-day work week?',
    worldYes: 71,
  ),
  _HistorySeed(
    category: 'PHILOSOPHY',
    prompt: 'Is a hot dog a sandwich?',
    worldYes: 45,
  ),
  _HistorySeed(
    category: 'SPORTS',
    prompt: 'Will the host nation reach the World Cup semi-finals?',
    worldYes: 59,
  ),
  _HistorySeed(
    category: 'BUSINESS',
    prompt: 'Will the four-day work week be the norm by 2035?',
    worldYes: 38,
  ),
  _HistorySeed(
    category: 'RELATIONSHIPS',
    prompt: 'Should couples share all their passwords?',
    worldYes: 51,
  ),
  _HistorySeed(
    category: 'AUTOMOTIVE',
    prompt: 'Will you ever own a fully self-driving car?',
    worldYes: 67,
  ),
  _HistorySeed(
    category: 'POLITICS',
    prompt: 'Should voting be mandatory?',
    worldYes: 44,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Is poutine the best late-night food?',
    worldYes: 72,
  ),
  _HistorySeed(
    category: 'GLOBAL EVENTS',
    prompt: 'Will humans set foot on Mars before 2040?',
    worldYes: 47,
  ),
  _HistorySeed(
    category: 'TECHNOLOGY',
    prompt: 'Do you trust AI to give medical advice?',
    worldYes: 29,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Is cancel culture mostly a good thing?',
    worldYes: 33,
  ),
  _HistorySeed(
    category: 'MONEY',
    prompt: 'Is owning a home still a realistic goal for your generation?',
    worldYes: 41,
  ),
  _HistorySeed(
    category: 'SCIENCE',
    prompt: 'Should we bring back extinct species?',
    worldYes: 49,
  ),
  _HistorySeed(
    category: 'PHILOSOPHY',
    prompt: 'Do people have genuine free will?',
    worldYes: 56,
  ),
  _HistorySeed(
    category: 'SPORTS',
    prompt: 'Is the GOAT debate impossible to settle?',
    worldYes: 77,
  ),
  _HistorySeed(
    category: 'RELATIONSHIPS',
    prompt: 'Should you stay friends with an ex?',
    worldYes: 43,
  ),
  _HistorySeed(
    category: 'BUSINESS',
    prompt: 'Are unpaid internships exploitative?',
    worldYes: 64,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Are physical books better than e-books?',
    worldYes: 64,
  ),
  _HistorySeed(
    category: 'POLITICS',
    prompt: 'Should there be an age limit for elected leaders?',
    worldYes: 71,
  ),
  _HistorySeed(
    category: 'TECHNOLOGY',
    prompt: 'Will passwords be obsolete within five years?',
    worldYes: 52,
  ),
  _HistorySeed(
    category: 'GLOBAL EVENTS',
    prompt: 'Will renewable energy power most of the world by 2040?',
    worldYes: 58,
  ),
  _HistorySeed(
    category: 'AUTOMOTIVE',
    prompt: 'Are electric vehicles overhyped?',
    worldYes: 39,
  ),
  _HistorySeed(
    category: 'MONEY',
    prompt: 'Should tipping be replaced by higher wages?',
    worldYes: 74,
  ),
  _HistorySeed(
    category: 'PHILOSOPHY',
    prompt: "Is it ever okay to lie to protect someone's feelings?",
    worldYes: 68,
  ),
  _HistorySeed(
    category: 'SPORTS',
    prompt: 'Is hockey the most exciting sport to watch live?',
    worldYes: 66,
  ),
  _HistorySeed(
    category: 'SCIENCE',
    prompt: 'Should human gene editing be allowed?',
    worldYes: 37,
  ),
  _HistorySeed(
    category: 'RELATIONSHIPS',
    prompt: 'Is a destination wedding worth the cost?',
    worldYes: 31,
  ),
  _HistorySeed(
    category: 'SPORTS',
    prompt: 'Should college athletes be paid like pros?',
    worldYes: 69,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Has streaming made music worse?',
    worldYes: 42,
  ),
  _HistorySeed(
    category: 'TECHNOLOGY',
    prompt: 'Do you read the terms before clicking agree?',
    worldYes: 12,
  ),
  _HistorySeed(
    category: 'BUSINESS',
    prompt: 'Will most offices be fully remote within ten years?',
    worldYes: 35,
  ),
  _HistorySeed(
    category: 'POLITICS',
    prompt: "Should social media verify every user's identity?",
    worldYes: 48,
  ),
  _HistorySeed(
    category: 'MONEY',
    prompt: 'Is cash going to disappear within your lifetime?',
    worldYes: 61,
  ),
  _HistorySeed(
    category: 'GLOBAL EVENTS',
    prompt: "Will English stay the world's common language in 2100?",
    worldYes: 73,
  ),
  _HistorySeed(
    category: 'PHILOSOPHY',
    prompt: 'Is a quiet life happier than an ambitious one?',
    worldYes: 57,
  ),
  _HistorySeed(
    category: 'AUTOMOTIVE',
    prompt: 'Should cities ban cars from downtown cores?',
    worldYes: 46,
  ),
  _HistorySeed(
    category: 'SCIENCE',
    prompt: 'Is there intelligent life elsewhere in the universe?',
    worldYes: 78,
  ),
  _HistorySeed(
    category: 'RELATIONSHIPS',
    prompt: 'Should you split the bill evenly on a first date?',
    worldYes: 53,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Are remakes ruining cinema?',
    worldYes: 59,
  ),
  _HistorySeed(
    category: 'SPORTS',
    prompt: 'Should video review be removed from soccer?',
    worldYes: 41,
  ),
  _HistorySeed(
    category: 'TECHNOLOGY',
    prompt: 'Would you let an AI manage your investments?',
    worldYes: 34,
  ),
  _HistorySeed(
    category: 'POLITICS',
    prompt: 'Should voting age be lowered to 16?',
    worldYes: 28,
  ),
  _HistorySeed(
    category: 'MONEY',
    prompt: 'Should you always carry some cash on you?',
    worldYes: 55,
  ),
  _HistorySeed(
    category: 'MONEY',
    prompt: 'Is a university degree still worth the money?',
    worldYes: 49,
  ),
  _HistorySeed(
    category: 'BUSINESS',
    prompt: "Should companies disclose everyone's salary?",
    worldYes: 44,
  ),
  _HistorySeed(
    category: 'PHILOSOPHY',
    prompt: 'Does luck matter more than hard work?',
    worldYes: 52,
  ),
  _HistorySeed(
    category: 'GLOBAL EVENTS',
    prompt: 'Will we have a universal basic income by 2050?',
    worldYes: 39,
  ),
  _HistorySeed(
    category: 'SCIENCE',
    prompt: 'Should we colonise the Moon before Mars?',
    worldYes: 63,
  ),
  _HistorySeed(
    category: 'RELATIONSHIPS',
    prompt: 'Is it fine to be on your phone around friends?',
    worldYes: 26,
  ),
  _HistorySeed(
    category: 'CULTURE',
    prompt: 'Is graffiti a legitimate art form?',
    worldYes: 67,
  ),
  _HistorySeed(
    category: 'SPORTS',
    prompt: "Will a woman coach a men's pro team this decade?",
    worldYes: 58,
  ),
  _HistorySeed(
    category: 'AUTOMOTIVE',
    prompt: 'Are road trips better than flying?',
    worldYes: 71,
  ),
  _HistorySeed(
    category: 'TECHNOLOGY',
    prompt: 'Will smartphones look obsolete in ten years?',
    worldYes: 64,
  ),
];

final demoQuestions = List<RtwQuestion>.generate(_historySeeds.length, (index) {
  final seed = _historySeeds[index];
  final date = DateTime(2026, 6, 25).subtract(Duration(days: index));
  final dailyKey =
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return RtwQuestion(
    id: '$dailyKey-history-$index',
    dailyKey: dailyKey,
    dateLabel: '${_monthsAbbr[date.month - 1]} ${date.day}',
    category: seed.category,
    prompt: seed.prompt,
    options: yesNo,
    worldShares: {'yes': seed.worldYes, 'no': 100 - seed.worldYes},
    totalAnswers: index == 0 ? 2431089 : 1400000 + ((index * 97123) % 1500000),
  );
});

List<HistoryEntry> buildDemoHistory() {
  return List.generate(demoQuestions.length, (index) {
    if (index == 0) {
      return HistoryEntry(
        question: demoQuestions[index],
        status: HistoryStatus.scored,
        selectedOptionId: 'yes',
        prediction: 71,
        readAccuracy: 87,
        readScoreDelta: 14,
      );
    }
    if (index % 13 == 6 && index != 0) {
      return HistoryEntry(
        question: demoQuestions[index],
        status: HistoryStatus.skipped,
      );
    }
    final question = demoQuestions[index];
    final worldYes = question.worldShareFor('yes');
    final flip = ((index * 37) % 100) < 24;
    final selected = worldYes >= 50
        ? (flip ? 'no' : 'yes')
        : (flip ? 'yes' : 'no');
    final sameWorld = selected == 'yes' ? worldYes : 100 - worldYes;
    final prediction = (sameWorld + ((index * 53) % 23) - 11).clamp(2, 98);
    return HistoryEntry(
      question: question,
      status: HistoryStatus.scored,
      selectedOptionId: selected,
      prediction: prediction,
      readAccuracy: (100 - ((sameWorld - prediction).abs() * 1.35).round())
          .clamp(71, 99),
    );
  });
}

const demoCategoryInsights = [
  CategoryInsight(name: 'Technology', score: 91, best: true),
  CategoryInsight(name: 'Science', score: 88, best: true),
  CategoryInsight(name: 'Money', score: 84, best: true),
  CategoryInsight(name: 'Sports', score: 58, best: false),
  CategoryInsight(name: 'Relationships', score: 63, best: false),
];

const demoFriends = [
  FriendRow(uid: 'demo-you', name: 'You', score: 1840, me: true),
  FriendRow(uid: 'demo-dana', name: 'Dana K.', score: 1792),
  FriendRow(uid: 'demo-marcus', name: 'Marcus R.', score: 1710),
];
