import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/log_service.dart';

/// Banner de AdMob con reintento automático.
///
/// En producción, si un anuncio falla al cargar (muy común en MIUI/Xiaomi por
/// "no fill" o por estrangulamiento de red), reintenta con backoff exponencial
/// en vez de desaparecer para siempre. Cada fallo se registra en [LogService]
/// con el código de error (2=red, 3=sin relleno) para diagnosticar por dispositivo.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _anuncioCargado = false;
  bool _fallido = false;

  // Control de reintentos con backoff exponencial.
  int _intentos = 0;
  static const int _maxIntentos = 5;
  Timer? _timerReintento;

  static String get _adUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/6300978111'
          : 'ca-app-pub-3940256099942544/2934735716';
    }
    // IDs de producción — reemplazar iOS con el aprobado por AdMob.
    return Platform.isAndroid
        ? 'ca-app-pub-6637517205793062/5967511694'
        : 'ca-app-pub-3940256099942544/2934735716';
  }

  static const double _alturaBanner = 50;

  @override
  void initState() {
    super.initState();
    _cargarAnuncio();
  }

  void _cargarAnuncio() {
    if (!mounted) return;
    setState(() {
      _fallido = false;
      _anuncioCargado = false;
    });
    _bannerAd?.dispose();
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          _intentos = 0;
          if (mounted) setState(() => _anuncioCargado = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          // code 2 = red, code 3 = sin relleno, code 0 = interno, code 1 = petición inválida.
          unawaited(LogService.instancia.registrar(
            'Banner AdMob FALLÓ (intento ${_intentos + 1}) '
            'code:${error.code} msg:${error.message}',
          ));
          if (!mounted) return;
          setState(() {
            _bannerAd = null;
            _fallido = true;
          });
          _programarReintento();
        },
      ),
    )..load();
  }

  void _programarReintento() {
    if (_intentos >= _maxIntentos) {
      unawaited(LogService.instancia.registrar(
        'Banner AdMob: agotados $_maxIntentos reintentos, se oculta',
      ));
      return;
    }
    _intentos++;
    // Backoff exponencial: 2, 4, 8, 16, 32 s (tope 60 s).
    final segundos = (1 << _intentos).clamp(2, 60);
    _timerReintento?.cancel();
    _timerReintento = Timer(Duration(seconds: segundos), _cargarAnuncio);
  }

  @override
  void dispose() {
    _timerReintento?.cancel();
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

    // En debug mostramos un placeholder para confirmar que el widget renderiza.
    if (kDebugMode) {
      return GestureDetector(
        onTap: _fallido ? _cargarAnuncio : null,
        child: Container(
          height: _alturaBanner,
          color: Colors.grey[200],
          child: Center(
            child: Text(
              _fallido
                  ? 'Anuncio no disponible (toca para reintentar)'
                  : 'Cargando anuncio...',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
