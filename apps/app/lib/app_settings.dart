import 'package:firebase_remote_config/firebase_remote_config.dart';

class AppSettings {
  const AppSettings({
    this.partyMode = true,
    this.friends = true,
    this.friendsLeaderboard = true,
    this.resultSharing = true,
    this.onboardingDemographics = true,
  });

  static const defaults = AppSettings();

  static const remoteConfigDefaults = {
    'daily_close_timezone': 'America/New_York',
    'minimum_scored_responses': 50,
    'read_score_start': 1500,
    'feature_party_mode': true,
    'feature_friends': true,
    'feature_friends_leaderboard': true,
    'feature_result_sharing': true,
    'feature_onboarding_demographics': true,
  };

  final bool partyMode;
  final bool friends;
  final bool friendsLeaderboard;
  final bool resultSharing;
  final bool onboardingDemographics;

  factory AppSettings.fromRemoteConfig(FirebaseRemoteConfig remoteConfig) {
    return AppSettings(
      partyMode: remoteConfig.getBool('feature_party_mode'),
      friends: remoteConfig.getBool('feature_friends'),
      friendsLeaderboard: remoteConfig.getBool('feature_friends_leaderboard'),
      resultSharing: remoteConfig.getBool('feature_result_sharing'),
      onboardingDemographics: remoteConfig.getBool(
        'feature_onboarding_demographics',
      ),
    );
  }
}
