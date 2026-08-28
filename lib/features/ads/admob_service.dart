import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NovaAdMob {
  NovaAdMob._();

  static const appId = 'ca-app-pub-3173771693054646~7238919629';
  static const bannerUnitId = 'ca-app-pub-3173771693054646/7833815992';
  static const rewardedUnitId = 'ca-app-pub-3173771693054646/1849037740';
  static const _premiumUntilKey = 'novaplay_premium_until_ms';

  static final NovaAdMob instance = NovaAdMob._();
  bool _loadingRewarded = false;

  Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  Future<bool> hasPremiumPass() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_premiumUntilKey) ?? 0;
    if (until <= DateTime.now().millisecondsSinceEpoch) {
      if (until != 0) await prefs.remove(_premiumUntilKey);
      return false;
    }
    return true;
  }

  Future<Duration?> premiumTimeRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final until = prefs.getInt(_premiumUntilKey) ?? 0;
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    return remaining > 0 ? Duration(milliseconds: remaining) : null;
  }

  Future<void> _savePremiumPass() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _premiumUntilKey,
      DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
  }

  Future<bool> requirePremium(BuildContext context, String featureName) async {
    if (await hasPremiumPass()) return true;
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlock premium features'),
        content: Text(
          'Watch 2 video ads to unlock all AI & conversion features for 24 hours!\n\nThis unlock includes $featureName and keeps the experience ad-free for the next 24 hours.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Watch 2 ads'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
    final unlocked = await _watchTwoRewardedAds(context);
    if (unlocked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Premium features unlocked for 24 hours')),
      );
    }
    return unlocked;
  }

  Future<RewardedAd?> _loadRewarded() async {
    if (_loadingRewarded) return null;
    _loadingRewarded = true;
    final result = await _loadRewardedInternal();
    _loadingRewarded = false;
    return result;
  }

  Future<RewardedAd?> _loadRewardedInternal() {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: completer.complete,
        onAdFailedToLoad: (_) => completer.complete(null),
      ),
    );
    return completer.future;
  }

  Future<bool> _watchTwoRewardedAds(BuildContext context) async {
    var completed = 0;
    for (var adNumber = 1; adNumber <= 2; adNumber++) {
      if (!context.mounted) return false;
      final ad = await _loadRewarded();
      if (ad == null || !context.mounted) {
        _showAdUnavailable(context);
        return false;
      }
      final rewarded = await _showRewarded(ad);
      if (!rewarded) return false;
      completed++;
    }
    if (completed == 2) {
      await _savePremiumPass();
      return true;
    }
    return false;
  }

  Future<bool> _showRewarded(RewardedAd ad) {
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (dismissedAd) {
        dismissedAd.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (failedAd, _) {
        failedAd.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(
      onUserEarnedReward: (rewardedAd, reward) {
        earned = true;
      },
    );
    return completer.future;
  }

  void _showAdUnavailable(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rewarded video is unavailable. Please try again later.'),
      ),
    );
  }
}
