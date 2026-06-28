import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'demo_data.dart';
import 'firestore_mappers.dart';
import 'models.dart';
import 'scoring.dart';

const _googleWebClientId = String.fromEnvironment('RTW_GOOGLE_WEB_CLIENT_ID');
const _googleIosClientId = String.fromEnvironment('RTW_GOOGLE_IOS_CLIENT_ID');

class RtwController extends ChangeNotifier {
  RtwController({required this.firebaseReady}) {
    history = buildDemoHistory();
    friends = List.of(demoFriends);
    categoryInsights = List.of(demoCategoryInsights);
    if (firebaseReady) {
      _hydrateFromFirebase();
    }
  }

  final bool firebaseReady;
  RtwQuestion today = todayQuestion;

  String? selectedOptionId;
  int prediction = 50;
  bool lockedToday = false;
  bool submitting = false;
  String? lastError;
  int liveCount = todayQuestion.totalAnswers;
  String displayName = 'Alex';
  String email = 'alex@email.com';
  bool dailyReminder = true;
  int avatarIndex = 0;
  DateTime? birthdate;
  String? gender;
  String? country;
  int readScore = 1840;
  int officialQuestionsAnswered = 142;
  String readScorePercentileLabel = 'Top 6% worldwide';
  int currentStreak = 7;
  String historyCategory = 'All';
  int partyIndex = 0;
  bool partyReveal = false;
  bool partyAnswerMode = false;
  String? partyAnswer;
  int partyPrediction = 50;
  String? selectedRevealQuestionId;
  late List<HistoryEntry> history;
  late List<FriendRow> friends;
  late List<CategoryInsight> categoryInsights;
  Timer? _liveTimer;
  Timer? _profileWriteDebounce;
  Future<void>? _googleSignInInitialization;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _liveQuestionSub;
  final List<StreamSubscription<dynamic>> _userSubscriptions = [];
  final Map<String, Map<String, dynamic>> _answerCache = {};
  final Map<String, Map<String, dynamic>> _scoreHistoryCache = {};
  final Map<String, Map<String, dynamic>> _resultCache = {};
  String? _boundUid;
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

  void _hydrateFromFirebase() {
    final firestore = FirebaseFirestore.instance;
    _liveQuestionSub = firestore
        .collection('questions')
        .where('status', isEqualTo: 'live')
        .limit(1)
        .snapshots()
        .listen(
          (snapshot) {
            if (snapshot.docs.isEmpty) return;
            final doc = snapshot.docs.first;
            final nextToday = questionFromFirestore(doc.id, doc.data());
            final isNewQuestion = nextToday.id != today.id;
            today = nextToday;
            liveCount = isNewQuestion
                ? nextToday.totalAnswers
                : liveCount.clamp(nextToday.totalAnswers, 1 << 31).toInt();
            if (isNewQuestion && !_answerCache.containsKey(nextToday.id)) {
              selectedOptionId = null;
              prediction = 50;
              lockedToday = false;
              _stopLiveTimer();
            }
            _syncTodayAnswerFromCache();
            notifyListeners();
          },
          onError: (Object error) {
            lastError = error.toString();
            notifyListeners();
          },
        );

    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _bindUser(user);
    });
  }

  void _bindUser(User? user) {
    final uid = user?.uid;
    final authDisplayName = user?.displayName;
    final authEmail = user?.email;
    if (_boundUid == uid) return;
    _clearUserSubscriptions();
    _boundUid = uid;
    _answerCache.clear();
    _scoreHistoryCache.clear();
    _resultCache.clear();
    if (uid == null) return;

    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(uid);
    _userSubscriptions.add(
      userRef.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null) return;
        displayName =
            _nonEmptyString(data['displayName']) ??
            authDisplayName ??
            displayName;
        email = _nonEmptyString(data['email']) ?? authEmail ?? email;
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
        _syncSelfFriendRow(uid);
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
        _syncTodayAnswerFromCache();
        _rebuildHistoryFromCache();
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
              (doc) =>
                  friendFromLeaderboardRow(doc.id, doc.data(), currentUid: uid),
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

  void _syncTodayAnswerFromCache() {
    final answer = _answerCache[today.id];
    if (answer == null) return;
    selectedOptionId = answer['selectedOptionId']?.toString();
    prediction = _intValue(answer['predictedShare'], fallback: prediction);
    lockedToday = true;
    _startLiveTimer();
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
    selectedOptionId = optionId;
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
    notifyListeners();
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
      notifyListeners();
      return true;
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
      notifyListeners();
      return true;
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
      notifyListeners();
      return true;
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
    submitting = true;
    lastError = null;
    notifyListeners();
    try {
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
      lockedToday = true;
      _startLiveTimer();
    } catch (error) {
      lastError = error.toString();
      if (!firebaseReady) {
        lockedToday = true;
        _startLiveTimer();
      }
    } finally {
      submitting = false;
      notifyListeners();
    }
  }

  void restartToday() {
    selectedOptionId = null;
    prediction = 50;
    lockedToday = false;
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
      dailyReminder = true;
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
      final token = await messaging.getToken(
        vapidKey: kIsWeb && webVapidKey.isNotEmpty ? webVapidKey : null,
      );
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
    if (!firebaseReady) return 'https://rtw.codes/demo';
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createShareLink');
      final result = await callable.call({'questionId': questionId});
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['url']?.toString() ?? 'https://rtw.codes/demo';
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return 'https://rtw.codes/demo';
    }
  }

  Future<String> createInviteUrl() async {
    unawaited(_logEvent('invite_friend'));
    if (!firebaseReady) return 'https://rtw.codes/demo';
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('createInvite');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['url']?.toString() ?? 'https://rtw.codes/demo';
    } catch (error) {
      lastError = error.toString();
      notifyListeners();
      return 'https://rtw.codes/demo';
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
      if (firebaseReady) {
        final callable = FirebaseFunctions.instanceFor(
          region: 'us-central1',
        ).httpsCallable('acceptInvite');
        await callable.call({'code': normalizedCode});
      }
      final hasInviteFriend = friends.any(
        (friend) => friend.name == 'New reader',
      );
      if (!hasInviteFriend) {
        friends = [
          ...friends,
          const FriendRow(name: 'New reader', score: 1500),
        ];
      }
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
    if (!firebaseReady) {
      return '/invite/${Uri.encodeComponent(normalizedCode)}';
    }
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
      displayName = 'Alex';
      email = 'alex@email.com';
      dailyReminder = true;
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
    _liveTimer ??= Timer.periodic(const Duration(milliseconds: 900), (_) {
      liveCount += 3;
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
    _scoreHistoryCache.clear();
    _stopLiveTimer();
    if (_resultCache.isEmpty) {
      history = buildDemoHistory()
          .map(
            (entry) => HistoryEntry(
              question: entry.question,
              status: HistoryStatus.skipped,
            ),
          )
          .toList();
    } else {
      _rebuildHistoryFromCache();
    }
    categoryInsights = const [];
    friends = const [FriendRow(name: 'You', score: 1500, me: true)];
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
    _authSub?.cancel();
    _liveQuestionSub?.cancel();
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
