import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  // Android uses live AdMob IDs. iOS remains on test IDs until real IDs are added.
  static const bool useTestAds = false;

  static const String _androidBannerTestId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _androidInterstitialTestId =
      'ca-app-pub-3940256099942544/1033173712';

  static const String _iosBannerTestId =
      'ca-app-pub-3940256099942544/2934735716';
  static const String _iosInterstitialTestId =
      'ca-app-pub-3940256099942544/4411468910';

  static const String _androidBannerProdId =
      'ca-app-pub-9901456896104761/3726101596';
  static const String _androidInterstitialProdId =
      'ca-app-pub-9901456896104761/1455161472';

  static const String _iosBannerProdId =
      'ca-app-pub-9901456896104761/5449787358';
  static const String _iosInterstitialProdId =
      'ca-app-pub-9901456896104761/1885946867';

  bool _isInitialized = false;
  bool _isLoadingInterstitial = false;
  bool _isShowingInterstitial = false;
  InterstitialAd? _interstitialAd;

  bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }

    return Platform.isAndroid || Platform.isIOS;
  }

  String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return useTestAds ? _androidBannerTestId : _androidBannerProdId;
    }
    return useTestAds ? _iosBannerTestId : _iosBannerProdId;
  }

  String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return useTestAds
          ? _androidInterstitialTestId
          : _androidInterstitialProdId;
    }
    return useTestAds ? _iosInterstitialTestId : _iosInterstitialProdId;
  }

  Future<void> initialize() async {
    if (_isInitialized || !isSupportedPlatform) {
      return;
    }

    await MobileAds.instance.initialize();
    _isInitialized = true;
    _loadInterstitial();
  }

  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }

  Future<void> maybeShowPostConversionInterstitial() async {
    if (!_isInitialized || _isShowingInterstitial) {
      return;
    }

    final ad = _interstitialAd;
    if (ad == null) {
      _loadInterstitial();
      return;
    }

    _interstitialAd = null;
    _isShowingInterstitial = true;

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        _isShowingInterstitial = false;
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingInterstitial = false;
        ad.dispose();
        _loadInterstitial();
      },
    );

    ad.show();
  }

  void _loadInterstitial() {
    if (!_isInitialized || _isLoadingInterstitial || _interstitialAd != null) {
      return;
    }

    _isLoadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _isLoadingInterstitial = false;
          _interstitialAd?.dispose();
          _interstitialAd = ad;
        },
        onAdFailedToLoad: (_) {
          _isLoadingInterstitial = false;
          _interstitialAd = null;
        },
      ),
    );
  }
}

class InlineBannerAdCard extends StatefulWidget {
  const InlineBannerAdCard({super.key});

  @override
  State<InlineBannerAdCard> createState() => _InlineBannerAdCardState();
}

class _InlineBannerAdCardState extends State<InlineBannerAdCard> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadBanner();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadBanner() async {
    if (!AdService.instance.isSupportedPlatform) {
      return;
    }

    final banner = BannerAd(
      adUnitId: AdService.instance.bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }

          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (!mounted) {
            return;
          }

          setState(() {
            _bannerAd = null;
            _isLoaded = false;
          });
        },
      ),
    );

    await banner.load();
  }

  @override
  Widget build(BuildContext context) {
    final bannerAd = _bannerAd;
    if (!_isLoaded || bannerAd == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8E0D3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            AdService.useTestAds ? 'Test ad' : 'Sponsored',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF7A7671),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: bannerAd.size.width.toDouble(),
              height: bannerAd.size.height.toDouble(),
              child: AdWidget(ad: bannerAd),
            ),
          ),
        ],
      ),
    );
  }
}
