import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firestore_mappers.dart';
import 'models.dart';
import 'scoring.dart';

const _googleWebClientId = String.fromEnvironment('RTW_GOOGLE_WEB_CLIENT_ID');
const _googleIosClientId = String.fromEnvironment('RTW_GOOGLE_IOS_CLIENT_ID');

class RtwController extends ChangeNotifier {
  RtwController({required this.firebaseReady}) {
    if (firebaseReady) {
      _hydrateFromFirebase();
    } else {
      lastError = 'Live data is unavailable. Firebase did not initialize.';
    }
  }

  final bool firebaseReady;
  RtwQuestion today = _emptyTodayQuestion;

  String? selectedOptionId;
  int prediction = 50;
  bool lockedToday = false;
  bool submitting = false;
  String? lastError;
  int liveCount = 0;
  String displayName = 'Reader';
  String email = '';
  bool emailVerified = false;
  String phoneNumber = '';
  bool phoneCodeSent = false;
  bool dailyReminder = false;
  int avatarIndex = 0;
  DateTime? birthdate;
  String? gender;
  String? country;
  int readScore = 1500;
  int officialQuestionsAnswered = 0;
  String readScorePercentileLabel = 'Unranked worldwide';
  int currentStreak = 0;
  String historyCategory = 'All';
  int partyIndex = 0;
  bool partyReveal = false;
  bool partyAnswerMode = false;
  String? partyAnswer;
  int partyPrediction = 50;
  String? selectedRevealQuestionId;
  List<HistoryEntry> history = const [];
  List<FriendRow> friends = const [];
  List<FriendAnswerComparison> friendAnswerComparisons = const [];
  bool loadingFriendAnswerComparisons = false;
  String? friendAnswerComparisonQuestionId;
  List<CategoryInsight> categoryInsights = const [];
  Timer? _liveTimer;
  Timer? _profileWriteDebounce;
  Future<void>? _googleSignInInitialization;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveQuestionSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _todayCounterSub;
  final List<StreamSubscription<dynamic>> _userSubscriptions = [];
  final Map<String, Map<String, dynamic>> _answerCache = {};
  final Map<String, Map<String, dynamic>> _answerDraftCache = {};
  final Map<String, Map<String, dynamic>> _scoreHistoryCache = {};
  final Map<String, Map<String, dynamic>> _resultCache = {};
  Timer? _draftWriteDebounce;
  String? _boundUid;
  String? _pendingHandoffQuestionId;
  String? _pendingHandoffOptionId;
  int? _pendingHandoffPrediction;
  ConfirmationResult? _webPhoneConfirmation;
  String? _phoneVerificationId;
  int? _phoneResendToken;
  String? _postOnboardingRoute;
  final Map<String, Future<String?>> _handoffRedemptions = {};
  final Map<String, String?> _redeemedHandoffRoutes = {};
  static const _historyCategoryOrder = [
    'TECHNOLOGY',
    'SCIENCE',
    'MONEY',
    'BUSINESS',
    'CULTURE',
    'POLITICS',
    'SPORTS',
    'RELATIONSHIPS',
    'PHILOSOPHY',
    'GLOBAL EVENTS',
    'AUTOMOTIVE',
  ];

  bool get hasTodayQuestion => today.id.isNotEmpty;
  bool get hasHistory => history.isNotEmpty;
  bool get hasPendingTodaySubmission =>
      selectedOptionId != null || _pendingHandoffOptionId != null;

  String consumePostOnboardingRoute() {
    final route = _postOnboardingRoute;
    _postOnboardingRoute = null;
    if (route != null && route.startsWith('/') && !route.startsWith('//')) {
      return route;
    }
    return hasPendingTodaySubmission ? '/today/predict' : '/today';
  }

  List<String> get categories {
    final present = history.map((entry) => entry.question.category).toSet();
    final ordered = [
      for (final category in _historyCategoryOrder)
        if (present.contains(category)) category,
    ];
    final orderedSet = ordered.toSet();
    final extras =
        present.where((category) => !orderedSet.contains(category)).toList()
          ..sort();
    return ['All', ...ordered, ...extras];
  }

  List<HistoryEntry> get filteredHistory {
    if (historyCategory == 'All') return history;
    return history
        .where((entry) => entry.question.category == historyCategory)
        .toList();
  }

  String get readScoreText => formattedReadScore(readScore);
  String get answeredCountText => answeredCountLabel(officialQuestionsAnswered);
  String get birthdateDisplay {
    final value = birthdate ?? DateTime(1989);
    return '${_shortMonthName(value.month)} ${value.day}, ${value.year} \u00B7 ${_ageForBirthdate(value)}';
  }

  String get genderDisplay => _nonEmptyString(gender) ?? 'Prefer not to say';
  String get countryDisplay => _nonEmptyString(country) ?? 'Canada';

  HistoryEntry get revealEntry {
    if (history.isEmpty) return _emptyHistoryEntry;
    final selectedId = selectedRevealQuestionId;
    if (selectedId != null) {
      for (final entry in history) {
        if (entry.question.id == selectedId) return entry;
      }
    }
    return history.first;
  }

  HistoryEntry revealEntryFor(String? questionId) {
    if (questionId == null || questionId.isEmpty) return revealEntry;
    return history.firstWhere(
      (entry) => entry.question.id == questionId,
      orElse: () => revealEntry,
    );
  }

  void selectRevealEntry(HistoryEntry entry) {
    selectedRevealQuestionId = entry.question.id;
    unawaited(
      _logEvent('view_reveal', {
        'question_id': entry.question.id,
        'category': entry.question.category,
        'status': entry.status.name,
      }),
    );
    notifyListeners();
  }

  String get selectedLabel {
    final id = selectedOptionId;
    if (id == null) return '';
    return today.option(id).label;
  }

  int get todayActualShare {
    final id = selectedOptionId;
    if (id == null) return 0;
    return today.worldShareFor(id);
  }

  String get predictionPhrase {
    final p = prediction;
    if (p <= 12) return 'Almost no one agrees with you';
    if (p <= 35) return "You're in the minority";
    if (p <= 45) return 'A little under half';
    if (p <= 55) return 'Split down the middle';
    if (p <= 70) return 'A clear majority';
    if (p <= 88) return 'Most of the world agrees';
    return 'Nearly everyone, you say';
  }

  String get nextRevealCountdownText {
    final closeAt = today.closeAt;
    if (closeAt == null) return 'Soon';
    final diff = closeAt.difference(DateTime.now());
    if (diff.inSeconds <= 0) return 'Ready';
    if (diff.inHours >= 24) {
      final days = diff.inDays;
      final hours = diff.inHours.remainder(24);
      return '${days}d ${hours}h';
    }
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = diff.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = diff.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _hydrateFromFirebase() {
    final firestore = FirebaseFirestore.instance;
    _liveQuestionSub = firestore
        .collection('questions')
        .where('status', isEqualTo: 'live')
        .orderBy('publishAt', descending: true)
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isEmpty) return;
            final doc = snapshot.docs.first;
            final nextToday = questionFromFirestore(doc.id, doc.data());
            final isNewQuestion = nextToday.id != today.id;
            today = nextToday;
            if (isNewQuestion || liveCount < nextToday.totalAnswers) {
              liveCount = nextToday.totalAnswers;
            }
            _bindQuestionCounter(nextToday.id);
            if (isNewQuestion && !_answerCache.containsKey(nextToday.id)) {
              // _syncTodayAnswerFromCache below restores any draft for the
              // new question; the previous question's lock must not carry
              // over or the draft is ignored and the app stays on /locked.
              selectedOptionId = null;
              prediction = 50;
              lockedToday = false;
              _stopLiveTimer();
            }
            _applyPendingHandoffAnswer();
            _syncTodayAnswerFromCache();
            notifyListeners();
          },
          onError: (Object error) {
            lastError = error.toString();
            notifyListeners();
          },
        );

    _authSub = FirebaseAuth.instance.userChanges().listen((user) {
      _bindUser(user);
    });
  }

  void _bindQuestionCounter(String questionId) {
    _todayCounterSub?.cancel();
    _todayCounterSub = FirebaseFirestore.instance
        .collection('questionCounters')
        .doc(questionId)
        .snapshots()
        .listen((snapshot) {
          final total = _intValue(snapshot.data()?['total']);
          liveCount = total > 0 ? total : today.totalAnswers;
          notifyListeners();
        }, onError: _handleReadError);
  }

  void _bindUser(User? user) {
    final uid = user?.uid;
    final authDisplayName = user?.displayName;
    final authEmail = user?.email;
    final authEmailVerified = user?.emailVerified ?? false;
    final authPhoneNumber = user?.phoneNumber;
    if (_boundUid == uid) {
      if (user != null) {
        _applyAuthUserDefaults(user, resetScoring: false);
        _scheduleAuthProfileWrite(user);
      }
      return;
    }
    _clearUserSubscriptions();
    _boundUid = uid;
    _answerCache.clear();
    _answerDraftCache.clear();
    _scoreHistoryCache.clear();
    _resultCache.clear();
    friendAnswerComparisons = const [];
    friendAnswerComparisonQuestionId = null;
    loadingFriendAnswerComparisons = false;
    if (user == null) return;
    _applyAuthUserDefaults(user);

    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(user.uid);
    _userSubscriptions.add(
      userRef.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null) {
          _scheduleAuthProfileWrite(user);
          return;
        }
        displayName =
            _nonEmptyString(data['displayName']) ??
            authDisplayName ??
            displayName;
        email = _nonEmptyString(data['email']) ?? authEmail ?? email;
        emailVerified = authEmailVerified;
        phoneNumber =
            _nonEmptyString(data['phoneNumber']) ??
            authPhoneNumber ??
            phoneNumber;
        dailyReminder = data['dailyReminder'] as bool? ?? dailyReminder;
        avatarIndex = _avatarIndexFromColor(data['avatarColor']);
        final demographics = _stringKeyedMap(data['demographics']);
        if (demographics != null) {
          birthdate = _parseBirthdate(demographics['birthdate']);
          gender = _nonEmptyString(demographics['gender']);
          country = _nonEmptyString(demographics['country']);
        }
        readScore = _intValue(data['readScore'], fallback: readScore);
        officialQuestionsAnswered = _intValue(
          data['officialQuestionsAnswered'],
          fallback: officialQuestionsAnswered,
        );
        currentStreak = _intValue(
          data['currentStreak'],
          fallback: currentStreak,
        );
        readScorePercentileLabel = scorePercentileLabel(
          data['readScorePercentile'] as num?,
        );
        _syncSelfFriendRow(user.uid);
        notifyListeners();
      }, onError: _handleReadError),
    );

    _userSubscriptions.add(
      userRef.collection('answers').snapshots().listen((snapshot) {
        _answerCache
          ..clear()
          ..addEntries(
            snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
          );
        final changed = _syncTodayAnswerFromCache();
        _rebuildHistoryFromCache();
        if (changed) notifyListeners();
      }, onError: _handleReadError),
    );

    _userSubscriptions.add(
      userRef.collection('answerDrafts').snapshots().listen((snapshot) {
        _answerDraftCache
          ..clear()
          ..addEntries(
            snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
          );
        if (_syncTodayAnswerFromCache()) notifyListeners();
      }, onError: _handleReadError),
    );

    _userSubscriptions.add(
      userRef.collection('scoreHistory').snapshots().listen((snapshot) {
        _scoreHistoryCache
          ..clear()
          ..addEntries(
            snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
          );
        _rebuildHistoryFromCache();
      }, onError: _handleReadError),
    );

    _userSubscriptions.add(
      firestore
          .collection('dailyResults')
          .where('status', isEqualTo: 'closed')
          .orderBy('closedAt', descending: true)
          .limit(90)
          .snapshots()
          .listen((snapshot) {
            _resultCache
              ..clear()
              ..addEntries(
                snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())),
              );
            _rebuildHistoryFromCache();
          }, onError: _handleReadError),
    );

    _userSubscriptions.add(
      userRef.collection('categoryStats').snapshots().listen((snapshot) {
        final stats =
            snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())).toList()
              ..sort((a, b) {
                final bScore = _intValue(b.value['smoothedCategoryScore']);
                final aScore = _intValue(a.value['smoothedCategoryScore']);
                return bScore.compareTo(aScore);
              });
        final best = stats
            .take(3)
            .map(
              (entry) =>
                  categoryInsightFromStat(entry.key, entry.value, best: true),
            )
            .toList();
        final misses = stats.reversed
            .take(2)
            .map(
              (entry) =>
                  categoryInsightFromStat(entry.key, entry.value, best: false),
            )
            .toList()
            .reversed
            .toList();
        if (best.isNotEmpty || misses.isNotEmpty) {
          categoryInsights = [...best, ...misses];
          notifyListeners();
        }
      }, onError: _handleReadError),
    );

    _userSubscriptions.add(
      userRef.collection('friends').snapshots().listen((snapshot) {
        final rows = snapshot.docs
            .where((doc) => doc.data()['status'] != 'removed')
            .map(
              (doc) => friendFromLeaderboardRow(
                doc.id,
                doc.data(),
                currentUid: user.uid,
              ),
            )
            .toList();
        friends = [
          FriendRow(uid: uid, name: 'You', score: readScore, me: true),
          ...rows,
        ]..sort((a, b) => b.score.compareTo(a.score));
        notifyListeners();
      }, onError: _handleReadError),
    );
  }

  void _applyAuthUserDefaults(User user, {bool resetScoring = true}) {
    displayName =
        _nonEmptyString(user.displayName) ??
        _displayNameFromEmail(user.email) ??
        'Reader';
    email = _nonEmptyString(user.email) ?? '';
    emailVerified = user.emailVerified;
    phoneNumber = _nonEmptyString(user.phoneNumber) ?? '';
    dailyReminder = false;
    avatarIndex = 0;
    birthdate = null;
    gender = null;
    country = null;
    if (resetScoring) {
      readScore = 1500;
      officialQuestionsAnswered = 0;
      readScorePercentileLabel = 'Unranked worldwide';
      currentStreak = 0;
      categoryInsights = const [];
      friends = [FriendRow(uid: user.uid, name: 'You', score: 1500, me: true)];
      selectedOptionId = null;
      prediction = 50;
      lockedToday = false;
      _stopLiveTimer();
    }
    notifyListeners();
  }

  void _scheduleAuthProfileWrite(User user) {
    if (!firebaseReady || FirebaseAuth.instance.currentUser?.uid != user.uid) {
      return;
    }
    unawaited(_writeInitialUserProfile(user));
  }

  Future<void> _writeInitialUserProfile(User user) async {
    final uid = user.uid;
    final displayName =
        _nonEmptyString(user.displayName) ??
        _displayNameFromEmail(user.email) ??
        'Reader';
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final snapshot = await userRef.get();
      final data = snapshot.data();
      final exists = snapshot.exists;
      await userRef.set({
        if (!exists || _nonEmptyString(data?['displayName']) == null)
          'displayName': displayName,
        if (!exists || _nonEmptyString(data?['email']) == null)
          'email': _nonEmptyString(user.email),
        if (!exists || _nonEmptyString(data?['phoneNumber']) == null)
          'phoneNumber': _nonEmptyString(user.phoneNumber),
        if (!exists || _nonEmptyString(data?['avatarColor']) == null)
          'avatarColor': _avatarColorName(avatarIndex),
        if (!exists || data?['dailyReminder'] is! bool)
          'dailyReminder': dailyReminder,
        if (!exists) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  bool get hasCompletedDemographics =>
      birthdate != null &&
      _nonEmptyString(gender) != null &&
      _nonEmptyString(country) != null;

  void _syncSelfFriendRow(String uid) {
    final hasSelf = friends.any((friend) => friend.me);
    if (!hasSelf) {
      friends = [
        FriendRow(uid: uid, name: 'You', score: readScore, me: true),
        ...friends,
      ]..sort((a, b) => b.score.compareTo(a.score));
      return;
    }
    friends =
        friends
            .map(
              (friend) => friend.me
                  ? FriendRow(
                      uid: uid,
                      name: 'You',
                      score: readScore,
                      me: true,
                      answersShared: friend.answersShared,
                    )
                  : friend,
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
  }

  bool _syncTodayAnswerFromCache() {
    final beforeOptionId = selectedOptionId;
    final beforePrediction = prediction;
    final beforeLockedToday = lockedToday;
    final answer = _answerCache[today.id];
    if (answer != null) {
      selectedOptionId = answer['selectedOptionId']?.toString();
      prediction = _intValue(answer['predictedShare'], fallback: prediction);
      lockedToday = true;
      _startLiveTimer();
      return beforeOptionId != selectedOptionId ||
          beforePrediction != prediction ||
          beforeLockedToday != lockedToday;
    }

    final draft = _answerDraftCache[today.id];
    if (draft == null || lockedToday) return false;
    final draftOptionId = _nonEmptyString(draft['selectedOptionId']);
    if (draftOptionId == null) return false;
    selectedOptionId = draftOptionId;
    prediction = _intValue(
      draft['predictedShare'],
      fallback: prediction,
    ).clamp(0, 100);
    return beforeOptionId != selectedOptionId ||
        beforePrediction != prediction ||
        beforeLockedToday != lockedToday;
  }

  void _applyPendingHandoffAnswer() {
    if (_pendingHandoffQuestionId == null ||
        _pendingHandoffQuestionId != today.id ||
        _pendingHandoffOptionId == null) {
      return;
    }
    selectedOptionId = _pendingHandoffOptionId;
    prediction = (_pendingHandoffPrediction ?? prediction).clamp(0, 100);
    lockedToday = false;
    _pendingHandoffQuestionId = null;
    _pendingHandoffOptionId = null;
    _pendingHandoffPrediction = null;
  }

  void _rebuildHistoryFromCache() {
    if (_resultCache.isEmpty) return;
    final nextHistory =
        _resultCache.entries
            .map(
              (entry) => historyEntryFromDailyResult(
                questionId: entry.key,
                resultData: entry.value,
                answerData: _answerCache[entry.key],
                scoreData: _scoreHistoryCache[entry.key],
              ),
            )
            .toList()
          ..sort((a, b) => b.question.dailyKey.compareTo(a.question.dailyKey));
    if (nextHistory.isNotEmpty) {
      history = nextHistory;
      if (selectedRevealQuestionId != null &&
          !history.any(
            (entry) => entry.question.id == selectedRevealQuestionId,
          )) {
        selectedRevealQuestionId = null;
      }
      notifyListeners();
    }
  }

  void _handleReadError(Object error) {
    lastError = error.toString();
    notifyListeners();
  }

  void selectOption(String optionId) {
    if (lockedToday) return;
    selectedOptionId = optionId;
    unawaited(_writeTodayDraft());
    unawaited(
      _logEvent('submit_answer', {
        'question_id': today.id,
        'category': today.category,
        'selected_option_id': optionId,
      }),
    );
    notifyListeners();
  }

  void setPrediction(int value) {
    prediction = value.clamp(0, 100);
    if (!lockedToday && selectedOptionId != null) {
      _scheduleTodayDraftWrite();
    }
    notifyListeners();
  }

  void _scheduleTodayDraftWrite() {
    _draftWriteDebounce?.cancel();
    _draftWriteDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_writeTodayDraft());
    });
  }

  Future<void> _writeTodayDraft() async {
    if (!firebaseReady || lockedToday || today.id.isEmpty) return;
    final optionId = selectedOptionId;
    if (optionId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('answerDrafts')
          .doc(today.id)
          .set({
            'questionId': today.id,
            'dailyKey': today.dailyKey,
            'selectedOptionId': optionId,
            'predictedShare': prediction,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _deleteTodayDraft() async {
    if (!firebaseReady || today.id.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('answerDrafts')
          .doc(today.id)
          .delete();
    } catch (_) {
      // Draft cleanup must not block the locked answer state.
    }
  }

  Future<bool> authenticateWithEmail({
    required String email,
    required String password,
    required bool creating,
  }) async {
    lastError = null;
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty || password.isEmpty) {
      lastError = 'Enter your email and password.';
      notifyListeners();
      return false;
    }
    if (creating && password.length < 8) {
      lastError = 'Use at least 8 characters for your password.';
      notifyListeners();
      return false;
    }
    if (!firebaseReady) {
      lastError = 'Live authentication is unavailable.';
      notifyListeners();
      return false;
    }
    try {
      final auth = FirebaseAuth.instance;
      if (creating) {
        final credential = EmailAuthProvider.credential(
          email: normalizedEmail,
          password: password,
        );
        final user = auth.currentUser;
        if (user != null && user.isAnonymous) {
          await user.linkWithCredential(credential);
        } else {
          await auth.createUserWithEmailAndPassword(
            email: normalizedEmail,
            password: password,
          );
        }
      } else {
        await auth.signInWithEmailAndPassword(
          email: normalizedEmail,
          password: password,
        );
      }
      if (creating) {
        unawaited(sendVerificationEmail(silent: true));
      }
      unawaited(
        _logEvent(creating ? 'sign_up' : 'login', {'method': 'password'}),
      );
      return true;
    } on FirebaseAuthException catch (error) {
      lastError = _authMessage(error);
      notifyListeners();
      return false;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> startPhoneSignIn(String rawPhoneNumber) async {
    lastError = null;
    phoneCodeSent = false;
    _webPhoneConfirmation = null;
    _phoneVerificationId = null;
    final normalizedPhoneNumber = _normalizePhoneNumber(rawPhoneNumber);
    if (normalizedPhoneNumber == null) {
      lastError = 'Enter a phone number with country code.';
      notifyListeners();
      return false;
    }
    if (!firebaseReady) {
      lastError = 'Live authentication is unavailable.';
      notifyListeners();
      return false;
    }

    try {
      final auth = FirebaseAuth.instance;
      phoneNumber = normalizedPhoneNumber;
      if (kIsWeb) {
        _webPhoneConfirmation = await auth.signInWithPhoneNumber(
          normalizedPhoneNumber,
        );
        phoneCodeSent = true;
        lastError = 'Code sent.';
        notifyListeners();
        unawaited(_logEvent('phone_code_sent'));
        return false;
      }

      final completer = Completer<bool>();
      await auth.verifyPhoneNumber(
        phoneNumber: normalizedPhoneNumber,
        forceResendingToken: _phoneResendToken,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          try {
            await _authenticateWithCredential(credential);
            phoneCodeSent = false;
            _phoneVerificationId = null;
            unawaited(_logEvent('login', {'method': 'phone'}));
            if (!completer.isCompleted) completer.complete(true);
          } on FirebaseAuthException catch (error) {
            lastError = _authMessage(error);
            if (!completer.isCompleted) completer.complete(false);
          } catch (error) {
            lastError = error.toString();
            if (!completer.isCompleted) completer.complete(false);
          }
          notifyListeners();
        },
        verificationFailed: (error) {
          lastError = _authMessage(error);
          phoneCodeSent = false;
          if (!completer.isCompleted) completer.complete(false);
          notifyListeners();
        },
        codeSent: (verificationId, resendToken) {
          _phoneVerificationId = verificationId;
          _phoneResendToken = resendToken;
          phoneCodeSent = true;
          lastError = 'Code sent.';
          if (!completer.isCompleted) completer.complete(false);
          notifyListeners();
          unawaited(_logEvent('phone_code_sent'));
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _phoneVerificationId = verificationId;
          notifyListeners();
        },
      );
      return completer.future.timeout(
        const Duration(seconds: 65),
        onTimeout: () => false,
      );
    } on FirebaseAuthException catch (error) {
      lastError = _authMessage(error);
      phoneCodeSent = false;
      notifyListeners();
      return false;
    } catch (error) {
      lastError = error.toString();
      phoneCodeSent = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyPhoneCode(String rawCode) async {
    lastError = null;
    final code = rawCode.trim().replaceAll(RegExp(r'\s+'), '');
    if (code.isEmpty) {
      lastError = 'Enter the code from the text message.';
      notifyListeners();
      return false;
    }
    if (!firebaseReady) {
      lastError = 'Live authentication is unavailable.';
      notifyListeners();
      return false;
    }

    try {
      if (kIsWeb) {
        final confirmation = _webPhoneConfirmation;
        if (confirmation == null) {
          lastError = 'Ask for a new code first.';
          notifyListeners();
          return false;
        }
        await confirmation.confirm(code);
      } else {
        final verificationId = _phoneVerificationId;
        if (verificationId == null || verificationId.isEmpty) {
          lastError = 'Ask for a new code first.';
          notifyListeners();
          return false;
        }
        final credential = PhoneAuthProvider.credential(
          verificationId: verificationId,
          smsCode: code,
        );
        await _authenticateWithCredential(credential);
      }
      phoneCodeSent = false;
      _webPhoneConfirmation = null;
      _phoneVerificationId = null;
      _phoneResendToken = null;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        phoneNumber = _nonEmptyString(user.phoneNumber) ?? phoneNumber;
        await _writeInitialUserProfile(user);
      }
      unawaited(_logEvent('login', {'method': 'phone'}));
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (error) {
      lastError = _authMessage(error);
      notifyListeners();
      return false;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return false;
    }
  }

  void resetPhoneSignIn() {
    phoneCodeSent = false;
    _webPhoneConfirmation = null;
    _phoneVerificationId = null;
    _phoneResendToken = null;
    lastError = null;
    notifyListeners();
  }

  /// v2: returning members (any room membership) land on their rooms;
  /// brand-new accounts get the onboarding demo first.
  Future<String> postAuthRoute() async {
    if (!firebaseReady) return '/onboarding';
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '/auth';
    try {
      final memberships = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('memberships')
          .limit(1)
          .get();
      return memberships.docs.isEmpty ? '/onboarding' : '/rooms';
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return '/onboarding';
    }
  }

  Future<String?> redeemAuthHandoff(
    String code, {
    String? fallbackRoute,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return null;
    if (_redeemedHandoffRoutes.containsKey(normalizedCode)) {
      return _redeemedHandoffRoutes[normalizedCode];
    }
    final inFlight = _handoffRedemptions[normalizedCode];
    if (inFlight != null) return inFlight;
    final future =
        _redeemAuthHandoff(normalizedCode, fallbackRoute: fallbackRoute).then((
          route,
        ) {
          if (route != null) _redeemedHandoffRoutes[normalizedCode] = route;
          return route;
        });
    _handoffRedemptions[normalizedCode] = future;
    future.whenComplete(() => _handoffRedemptions.remove(normalizedCode));
    return future;
  }

  Future<String?> _redeemAuthHandoff(
    String code, {
    String? fallbackRoute,
  }) async {
    lastError = null;
    if (!firebaseReady) {
      lastError = 'Live authentication is unavailable.';
      notifyListeners();
      return null;
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('redeemAuthHandoff');
      final result = await callable.call({'code': code});
      final data = Map<String, dynamic>.from(result.data as Map);
      final customToken = _nonEmptyString(data['customToken']);
      if (customToken == null) {
        throw StateError('Auth handoff did not return a sign-in token.');
      }
      _pendingHandoffQuestionId = _nonEmptyString(data['questionId']);
      _pendingHandoffOptionId = _nonEmptyString(data['selectedOptionId']);
      _pendingHandoffPrediction = _intValue(
        data['predictedShare'],
        fallback: prediction,
      );
      final hasPendingHandoffAnswer =
          _pendingHandoffQuestionId != null && _pendingHandoffOptionId != null;
      if (hasPendingHandoffAnswer) {
        _postOnboardingRoute = '/today/predict';
      }
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      _applyPendingHandoffAnswer();
      final completedDemographics = data['hasCompletedDemographics'] == true;
      if (!completedDemographics) return '/onboarding';
      if (hasPendingHandoffAnswer) {
        return '/today/predict';
      }
      final targetRoute =
          _nonEmptyString(data['targetRoute']) ??
          _nonEmptyString(fallbackRoute) ??
          '/today';
      return targetRoute.startsWith('/') && !targetRoute.startsWith('//')
          ? targetRoute
          : '/today';
    } on FirebaseFunctionsException catch (error) {
      lastError = error.message ?? error.code;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (error) {
      lastError = _authMessage(error);
      notifyListeners();
      return null;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> authenticateWithGoogle() {
    if (!kIsWeb) return _authenticateWithNativeGoogle();
    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile');
    return _authenticateWithProvider(provider);
  }

  Future<bool> authenticateWithApple() {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return _authenticateWithProvider(provider);
  }

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleSignInInitialization ??= GoogleSignIn.instance.initialize(
      clientId:
          defaultTargetPlatform == TargetPlatform.iOS &&
              _googleIosClientId.isNotEmpty
          ? _googleIosClientId
          : null,
      serverClientId: _googleWebClientId.isNotEmpty ? _googleWebClientId : null,
    );
  }

  Future<bool> _authenticateWithNativeGoogle() async {
    lastError = null;
    if (!firebaseReady) {
      lastError = 'Live authentication is unavailable.';
      notifyListeners();
      return false;
    }
    try {
      await _ensureGoogleSignInInitialized();
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw FirebaseAuthException(
          code: 'missing-google-id-token',
          message: 'Google sign-in did not return an ID token.',
        );
      }
      await _authenticateWithCredential(
        GoogleAuthProvider.credential(idToken: idToken),
      );
      unawaited(_logEvent('login', {'method': 'google.com'}));
      return true;
    } on GoogleSignInException catch (error) {
      lastError = _googleSignInMessage(error);
      notifyListeners();
      return false;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'credential-already-in-use' ||
          error.code == 'provider-already-linked') {
        await _signInWithFreshGoogleCredential();
        unawaited(_logEvent('login', {'method': 'google.com'}));
        return true;
      }
      lastError = _authMessage(error);
      notifyListeners();
      return false;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> _signInWithFreshGoogleCredential() async {
    await _ensureGoogleSignInInitialized();
    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: const ['email', 'profile'],
    );
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google sign-in did not return an ID token.',
      );
    }
    await FirebaseAuth.instance.signInWithCredential(
      GoogleAuthProvider.credential(idToken: idToken),
    );
  }

  Future<void> _authenticateWithCredential(AuthCredential credential) async {
    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user != null && user.isAnonymous) {
      await user.linkWithCredential(credential);
    } else {
      await auth.signInWithCredential(credential);
    }
  }

  Future<bool> _authenticateWithProvider(AuthProvider provider) async {
    lastError = null;
    if (!firebaseReady) {
      lastError = 'Live authentication is unavailable.';
      notifyListeners();
      return false;
    }
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser;
      if (user != null && user.isAnonymous) {
        if (kIsWeb) {
          await user.linkWithPopup(provider);
        } else {
          await user.linkWithProvider(provider);
        }
      } else if (kIsWeb) {
        await auth.signInWithPopup(provider);
      } else {
        await auth.signInWithProvider(provider);
      }
      unawaited(_logEvent('login', {'method': provider.providerId}));
      return true;
    } on FirebaseAuthException catch (error) {
      if (error.code == 'credential-already-in-use' ||
          error.code == 'provider-already-linked') {
        if (kIsWeb) {
          await FirebaseAuth.instance.signInWithPopup(provider);
        } else {
          await FirebaseAuth.instance.signInWithProvider(provider);
        }
        unawaited(_logEvent('login', {'method': provider.providerId}));
        return true;
      }
      lastError = _authMessage(error);
      notifyListeners();
      return false;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    lastError = null;
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      lastError = 'Enter your email first.';
      notifyListeners();
      return;
    }
    if (!firebaseReady) {
      lastError =
          'Password reset will be available after Firebase is configured.';
      notifyListeners();
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: normalizedEmail,
      );
      lastError = 'Password reset email sent.';
      notifyListeners();
    } on FirebaseAuthException catch (error) {
      lastError = _authMessage(error);
      notifyListeners();
    }
  }

  Future<void> sendVerificationEmail({bool silent = false}) async {
    lastError = null;
    if (!firebaseReady) {
      if (!silent) {
        lastError = 'Live authentication is unavailable.';
        notifyListeners();
      }
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _nonEmptyString(user.email) == null) {
      if (!silent) {
        lastError = 'Add an email address before verifying.';
        notifyListeners();
      }
      return;
    }
    await user.reload();
    final refreshed = FirebaseAuth.instance.currentUser;
    emailVerified = refreshed?.emailVerified ?? emailVerified;
    if (emailVerified) {
      if (!silent) {
        lastError = 'Email is already verified.';
        notifyListeners();
      }
      return;
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('sendVerificationEmail');
      await callable.call();
      if (!silent) {
        lastError = 'Verification email sent.';
        notifyListeners();
      }
    } on FirebaseFunctionsException catch (error) {
      if (!silent) {
        lastError = error.message ?? error.code;
        notifyListeners();
      }
    } catch (error) {
      if (!silent) {
        lastError = error.toString();
        notifyListeners();
      }
    }
  }

  String _authMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'email-already-in-use':
        return 'That email already has an account. Sign in instead.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password was not recognized.';
      case 'weak-password':
        return 'Use a stronger password.';
      case 'invalid-phone-number':
        return 'Enter a phone number with country code.';
      case 'missing-verification-code':
        return 'Enter the code from the text message.';
      case 'invalid-verification-code':
        return 'That code was not recognized.';
      case 'session-expired':
        return 'That code expired. Ask for a new one.';
      case 'quota-exceeded':
      case 'too-many-requests':
        return 'Too many code requests. Try again later.';
      case 'captcha-check-failed':
        return 'Phone verification failed. Try again.';
      case 'network-request-failed':
        return 'Network error. Try again.';
      case 'popup-closed-by-user':
      case 'canceled':
        return 'Sign-in was cancelled.';
      case 'missing-google-id-token':
        return 'Google sign-in did not return an ID token.';
      default:
        return error.message ?? error.code;
    }
  }

  String _googleSignInMessage(GoogleSignInException error) {
    switch (error.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Sign-in was cancelled.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google sign-in is not configured for this app yet.';
      default:
        return error.description ?? 'Google sign-in failed.';
    }
  }

  Future<void> lockPrediction() async {
    if (selectedOptionId == null) return;
    _draftWriteDebounce?.cancel();
    submitting = true;
    lockedToday = true;
    lastError = null;
    _startLiveTimer();
    notifyListeners();
    try {
      if (!firebaseReady) {
        throw StateError('Live data is unavailable.');
      }
      if (firebaseReady) {
        final callable = FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('submitPrediction');
        await callable.call({
          'questionId': today.id,
          'selectedOptionId': selectedOptionId,
          'predictedShare': prediction,
        });
      }
      unawaited(
        _logEvent('submit_prediction', {
          'question_id': today.id,
          'category': today.category,
          'selected_option_id': selectedOptionId!,
          'predicted_share': prediction,
        }),
      );
      unawaited(
        _logEvent('lock_prediction', {
          'question_id': today.id,
          'category': today.category,
          'predicted_share': prediction,
        }),
      );
      unawaited(_deleteTodayDraft());
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'already-exists') {
        lockedToday = true;
        _startLiveTimer();
        unawaited(_deleteTodayDraft());
      } else {
        lockedToday = false;
        _stopLiveTimer();
        lastError = error.message ?? error.code;
      }
    } catch (error) {
      lockedToday = false;
      _stopLiveTimer();
      lastError = error.toString();
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void restartToday() {
    if (lockedToday) return;
    selectedOptionId = null;
    prediction = 50;
    _stopLiveTimer();
    notifyListeners();
  }

  void setHistoryCategory(String category) {
    historyCategory = category;
    notifyListeners();
  }

  void revealSkipped(HistoryEntry entry) {
    final index = history.indexOf(entry);
    if (index < 0) return;
    history[index] = entry.copyWith(
      status: HistoryStatus.revealed,
      peeked: true,
    );
    unawaited(
      _logEvent('view_reveal', {
        'question_id': entry.question.id,
        'category': entry.question.category,
        'source': 'peek',
      }),
    );
    notifyListeners();
  }

  Future<void> replayHistory(
    HistoryEntry entry,
    String optionId,
    int replayPrediction,
  ) {
    return savePracticeAnswer(
      entry,
      optionId,
      replayPrediction,
      source: 'history-replay',
    );
  }

  Future<void> savePracticeAnswer(
    HistoryEntry entry,
    String optionId,
    int practicePrediction, {
    String source = 'history-replay',
  }) async {
    final index = history.indexOf(entry);
    if (index < 0) return;
    if (entry.status == HistoryStatus.scored &&
        !entry.played &&
        !entry.peeked) {
      return;
    }
    final actualShare = entry.question.worldShareFor(optionId);
    history[index] = entry.copyWith(
      status: HistoryStatus.revealed,
      selectedOptionId: optionId,
      prediction: practicePrediction,
      readAccuracy: calculateReadAccuracy(
        predictedShare: practicePrediction,
        actualShare: actualShare,
      ),
      officialCountedTowardScore: false,
      played: true,
    );
    unawaited(
      _logEvent('answer_past_question', {
        'question_id': entry.question.id,
        'category': entry.question.category,
        'source': source,
        'selected_option_id': optionId,
        'predicted_share': practicePrediction,
      }),
    );
    notifyListeners();
    if (!firebaseReady) return;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('savePracticeAnswer');
      await callable.call({
        'questionId': entry.question.id,
        'selectedOptionId': optionId,
        'predictedShare': practicePrediction,
        'source': source,
      });
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> toggleFriendAnswerVisibility(FriendRow target) async {
    final friendUid = target.uid;
    final nextShared = !target.answersShared;
    friends = friends
        .map(
          (friend) => friend.uid == friendUid || friend.name == target.name
              ? friend.copyWith(answersShared: nextShared)
              : friend,
        )
        .toList();
    notifyListeners();
    if (!firebaseReady || friendUid == null || target.me) return;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('setFriendAnswerVisibility');
      await callable.call({
        'friendUid': friendUid,
        'answersShared': nextShared,
      });
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> loadFriendAnswerComparisons(String questionId) async {
    if (!firebaseReady || questionId.isEmpty) return;
    if (loadingFriendAnswerComparisons ||
        friendAnswerComparisonQuestionId == questionId) {
      return;
    }
    loadingFriendAnswerComparisons = true;
    friendAnswerComparisonQuestionId = questionId;
    friendAnswerComparisons = const [];
    notifyListeners();
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('getLeaderboard');
      final result = await callable.call({
        'mode': 'friendAnswerComparisons',
        'questionId': questionId,
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final rows = data['rows'] as List? ?? const [];
      friendAnswerComparisons = rows
          .whereType<Map>()
          .map(
            (row) =>
                friendAnswerComparisonFromData(Map<String, dynamic>.from(row)),
          )
          .where((row) => row.uid.isNotEmpty && row.selectedOptionId.isNotEmpty)
          .toList();
    } catch (error) {
      lastError = error.toString();
      // Keep friendAnswerComparisonQuestionId set: the reveal screen requests
      // a load whenever it differs from the shown question, so clearing it
      // here would retry a failing callable on every rebuild.
    } finally {
      loadingFriendAnswerComparisons = false;
      notifyListeners();
    }
  }

  Future<void> removeFriend(FriendRow target) async {
    final friendUid = target.uid;
    friends = friends
        .where(
          (friend) => friend.me
              ? true
              : friendUid != null
              ? friend.uid != friendUid
              : friend.name != target.name,
        )
        .toList();
    notifyListeners();
    if (!firebaseReady || friendUid == null || target.me) return;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('removeFriend');
      await callable.call({'friendUid': friendUid});
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  void setDisplayName(String value) {
    displayName = value;
    notifyListeners();
    _scheduleProfileWrite({'displayName': value.trim()});
  }

  void cycleAvatar() {
    avatarIndex = (avatarIndex + 1) % 4;
    notifyListeners();
    _scheduleProfileWrite({'avatarColor': _avatarColorName(avatarIndex)});
  }

  Future<void> saveDemographics({
    DateTime? birthdate,
    String? gender,
    String? country,
  }) async {
    this.birthdate = birthdate;
    this.gender = _nonEmptyString(gender);
    this.country = _nonEmptyString(country);
    notifyListeners();
    await _writeUserProfile({
      'demographics': {
        'birthdate': birthdate == null ? null : _dateToIsoString(birthdate),
        'gender': this.gender,
        'country': this.country,
      },
    });
  }

  Future<void> toggleReminder() async {
    final next = !dailyReminder;
    lastError = null;
    if (!next) {
      dailyReminder = false;
      notifyListeners();
      await _setCurrentNotificationTokenEnabled(false);
      await _writeUserProfile({'dailyReminder': false});
      unawaited(_logEvent('notification_opt_out'));
      return;
    }
    if (!firebaseReady) {
      dailyReminder = false;
      lastError = 'Live notifications are unavailable.';
      notifyListeners();
      return;
    }
    try {
      const webVapidKey = String.fromEnvironment('RTW_WEB_PUSH_VAPID_KEY');
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        dailyReminder = false;
        lastError = 'Notifications were not enabled.';
        notifyListeners();
        return;
      }
      await _ensureApplePushToken(messaging);
      final token = await messaging.getToken(
        vapidKey: kIsWeb && webVapidKey.isNotEmpty ? webVapidKey : null,
      );
      if (token == null || token.isEmpty) {
        throw StateError('Push notification token was not available.');
      }
      await _writeNotificationToken(token: token, enabled: true);
      dailyReminder = true;
      await _writeUserProfile({'dailyReminder': true});
      unawaited(_logEvent('notification_opt_in'));
      notifyListeners();
    } catch (error) {
      dailyReminder = false;
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _ensureApplePushToken(FirebaseMessaging messaging) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS)) {
      return;
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final token = await messaging.getAPNSToken();
      if (token != null && token.isNotEmpty) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw StateError(
      'Apple push registration is not ready. Check APNs entitlements and Firebase Cloud Messaging setup.',
    );
  }

  Future<void> _setCurrentNotificationTokenEnabled(bool enabled) async {
    if (!firebaseReady) return;
    try {
      const webVapidKey = String.fromEnvironment('RTW_WEB_PUSH_VAPID_KEY');
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && webVapidKey.isNotEmpty ? webVapidKey : null,
      );
      await _writeNotificationToken(token: token, enabled: enabled);
    } catch (_) {
      // Opt-out state is also stored on the user profile; token cleanup is best-effort.
    }
  }

  Future<void> _writeNotificationToken({
    required String? token,
    required bool enabled,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token == null || token.isEmpty) return;
    final tokenId = token.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notificationTokens')
        .doc(tokenId)
        .set({
          'token': token,
          'platform': defaultTargetPlatform.name,
          'enabled': enabled,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  void resetParty() {
    partyIndex = 0;
    partyReveal = false;
    partyAnswerMode = false;
    partyAnswer = null;
    partyPrediction = 50;
    notifyListeners();
  }

  void setPartyMode(bool answerMode) {
    partyAnswerMode = answerMode;
    partyReveal = false;
    partyAnswer = null;
    notifyListeners();
  }

  void answerParty(String optionId) {
    partyAnswer = optionId;
    notifyListeners();
  }

  void setPartyPrediction(int value) {
    partyPrediction = value.clamp(0, 100);
    notifyListeners();
  }

  void revealPartyCard() {
    partyReveal = true;
    notifyListeners();
  }

  void nextPartyCard({int? deckLength}) {
    final maxLength = deckLength ?? history.length;
    if (partyIndex < maxLength - 1) {
      partyIndex += 1;
      partyReveal = false;
      partyAnswer = null;
      partyPrediction = 50;
    }
    notifyListeners();
  }

  Future<String> createResultShareUrl(String questionId) async {
    unawaited(_logEvent('share_result', {'question_id': questionId}));
    if (!firebaseReady) {
      lastError = 'Live sharing is unavailable.';
      notifyListeners();
      return '';
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createShareLink');
      final result = await callable.call({'questionId': questionId});
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['shortUrl']?.toString() ?? data['url']?.toString() ?? '';
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return '';
    }
  }

  Future<String> createInviteUrl() async {
    unawaited(_logEvent('invite_friend'));
    if (!firebaseReady) {
      lastError = 'Live invites are unavailable.';
      notifyListeners();
      return '';
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createInvite');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['shortUrl']?.toString() ?? data['url']?.toString() ?? '';
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return '';
    }
  }

  Future<bool> acceptInvite(String code) async {
    lastError = null;
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      lastError = 'Invite code is missing.';
      notifyListeners();
      return false;
    }
    try {
      if (!firebaseReady) {
        throw StateError('Live invites are unavailable.');
      }
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('acceptInvite');
      await callable.call({'code': normalizedCode});
      unawaited(_logEvent('join_friend_group', {'code': normalizedCode}));
      notifyListeners();
      return true;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<String?> resolveShortCodeRoute(String code) async {
    lastError = null;
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) {
      lastError = 'Link code is missing.';
      notifyListeners();
      return null;
    }
    if (!firebaseReady) return null;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('resolveShortCode');
      final result = await callable.call({'code': normalizedCode});
      final data = Map<String, dynamic>.from(result.data as Map);
      final route = data['route']?.toString();
      if (route != null && route.startsWith('/')) return route;

      final type = data['type']?.toString();
      final targetId = data['targetId']?.toString();
      if (type == 'invite') {
        return '/invite/${Uri.encodeComponent(normalizedCode)}';
      }
      if (type == 'result' && targetId != null && targetId.isNotEmpty) {
        return '/reveal/${Uri.encodeComponent(targetId)}?code=${Uri.encodeComponent(normalizedCode)}';
      }
      lastError = 'This link is not valid.';
      notifyListeners();
      return null;
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> signOut() async {
    lastError = null;
    try {
      if (firebaseReady) {
        await FirebaseAuth.instance.signOut();
      }
      _clearUserSubscriptions();
      _boundUid = null;
      displayName = 'Reader';
      email = '';
      emailVerified = false;
      phoneNumber = '';
      phoneCodeSent = false;
      dailyReminder = false;
      avatarIndex = 0;
      birthdate = null;
      gender = null;
      country = null;
      _resetScoringData();
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _logEvent(String name, [Map<String, Object>? parameters]) async {
    if (!firebaseReady) return;
    try {
      await FirebaseAnalytics.instance.logEvent(
        name: name,
        parameters: parameters,
      );
    } catch (_) {
      // Analytics should never block gameplay or account actions.
    }
  }

  Future<void> clearAllData() async {
    lastError = null;
    try {
      if (firebaseReady) {
        final callable = FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('clearMyData');
        await callable.call();
      }
      _resetScoringData();
      notifyListeners();
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  void _startLiveTimer() {
    if (_liveTimer?.isActive == true) return;
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!lockedToday) {
        _stopLiveTimer();
        return;
      }
      notifyListeners();
    });
  }

  void _stopLiveTimer() {
    _liveTimer?.cancel();
    _liveTimer = null;
  }

  void _scheduleProfileWrite(Map<String, Object?> values) {
    if (!firebaseReady) return;
    _profileWriteDebounce?.cancel();
    _profileWriteDebounce = Timer(const Duration(milliseconds: 500), () {
      _writeUserProfile(values);
    });
  }

  Future<void> _writeUserProfile(Map<String, Object?> values) async {
    if (!firebaseReady) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        ...values,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
    }
  }

  void _resetScoringData() {
    selectedOptionId = null;
    prediction = 50;
    lockedToday = false;
    submitting = false;
    readScore = 1500;
    officialQuestionsAnswered = 0;
    readScorePercentileLabel = 'Unranked worldwide';
    currentStreak = 0;
    historyCategory = 'All';
    partyIndex = 0;
    partyReveal = false;
    partyAnswerMode = false;
    partyAnswer = null;
    partyPrediction = 50;
    selectedRevealQuestionId = null;
    _answerCache.clear();
    _answerDraftCache.clear();
    _scoreHistoryCache.clear();
    _stopLiveTimer();
    history = const [];
    if (_resultCache.isNotEmpty) _rebuildHistoryFromCache();
    categoryInsights = const [];
    friends = const [FriendRow(name: 'You', score: 1500, me: true)];
    friendAnswerComparisons = const [];
    friendAnswerComparisonQuestionId = null;
    loadingFriendAnswerComparisons = false;
  }

  void _clearUserSubscriptions() {
    for (final subscription in _userSubscriptions) {
      subscription.cancel();
    }
    _userSubscriptions.clear();
  }

  @override
  void dispose() {
    _profileWriteDebounce?.cancel();
    _draftWriteDebounce?.cancel();
    _authSub?.cancel();
    _liveQuestionSub?.cancel();
    _todayCounterSub?.cancel();
    _clearUserSubscriptions();
    _stopLiveTimer();
    super.dispose();
  }
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return text;
}

String? _normalizePhoneNumber(String value) {
  final compact = value.trim().replaceAll(RegExp(r'[\s().-]+'), '');
  if (RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(compact)) return compact;
  final digits = compact.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '+1$digits';
  if (digits.length == 11 && digits.startsWith('1')) return '+$digits';
  return null;
}

const _emptyOptions = [
  RtwOption(id: 'yes', label: 'Yes'),
  RtwOption(id: 'no', label: 'No'),
];

const _emptyTodayQuestion = RtwQuestion(
  id: '',
  dailyKey: '',
  dateLabel: '',
  category: '',
  prompt: '',
  options: _emptyOptions,
  worldShares: {},
);

const _emptyHistoryEntry = HistoryEntry(
  question: _emptyTodayQuestion,
  status: HistoryStatus.skipped,
);

String? _displayNameFromEmail(String? value) {
  final email = _nonEmptyString(value);
  if (email == null) return null;
  final localPart = email.split('@').first.trim();
  if (localPart.isEmpty) return null;
  final cleaned = localPart
      .replaceAll(RegExp(r'[._+-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.isEmpty) return null;
  return cleaned
      .split(' ')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

DateTime? _parseBirthdate(Object? value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return DateTime(date.year, date.month, date.day);
  }
  if (value is DateTime) {
    return DateTime(value.year, value.month, value.day);
  }
  final text = _nonEmptyString(value);
  if (text == null) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _dateToIsoString(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _shortMonthName(int month) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return months[(month - 1).clamp(0, 11).toInt()];
}

int _ageForBirthdate(DateTime birthdate) {
  final now = DateTime.now();
  var age = now.year - birthdate.year;
  final birthdayPassed =
      now.month > birthdate.month ||
      (now.month == birthdate.month && now.day >= birthdate.day);
  if (!birthdayPassed) age -= 1;
  return age.clamp(0, 130).toInt();
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int _avatarIndexFromColor(Object? value) {
  return switch (value?.toString()) {
    'clay' => 1,
    'green' => 2,
    'ink' => 3,
    _ => 0,
  };
}

String _avatarColorName(int index) {
  return switch (index % 4) {
    1 => 'clay',
    2 => 'green',
    3 => 'ink',
    _ => 'blue',
  };
}
