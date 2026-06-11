import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _anuncioCargado = false;
  bool _fallido = false;

  // IDs de prueba — cambiar a los reales cuando AdMob apruebe la cuenta:
  // Android real: ca-app-pub-6637517205793062/5967511694
  static String get _adUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';

  static const double _alturaBanner = 50;

  @override
  void initState() {
    super.initState();
    _cargarAnuncio();
  }

  void _cargarAnuncio() {
    setState(() {
      _fallido = false;
      _anuncioCargado = false;
    });
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _anuncioCargado = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner AdMob error: ${error.message}');
          ad.dispose();
          if (mounted) setState(() { _bannerAd = null; _fallido = true; });
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_anuncioCargado && _bannerAd != null) {
      return SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }

    // En debug mostramos un placeholder para confirmar que el widget renderiza
    if (kDebugMode) {
      return GestureDetector(
        onTap: _fallido ? _cargarAnuncio : null,
        child: Container(
          height: _alturaBanner,
          color: Colors.grey[200],
          child: Center(
            child: Text(
              _fallido ? 'Anuncio no disponible (toca para reintentar)' : 'Cargando anuncio...',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
