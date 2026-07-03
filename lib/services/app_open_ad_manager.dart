import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'log_service.dart';

/// Gestor del App Open Ad de AdMob.
///
/// Muestra un anuncio a pantalla completa al volver la app a primer plano,
/// pero SOLO cuando es seguro hacerlo. La política de candados vive en el
/// método puro [puedeMostrar], separada del plumbing del SDK para poder
/// probarla en unit tests con un reloj inyectado.
///
/// Candados obligatorios (ver [puedeMostrar]):
/// 1. NUNCA sobre una alarma sonando (`hayAlarmaSonando`).
/// 2. NUNCA en arranque en frío / apertura por alarma (requiere `_estuvoEnPausa`).
/// 3. Frequency cap: como máximo 1 anuncio cada [frecuenciaMinima] (4 h por defecto).
///
/// Nunca se instancia ni se muestra desde PantallaAlarmaActiva ni desde
/// diálogos: solo lo usa la pantalla principal en su ciclo de vida.
class AppOpenAdManager {
  AppOpenAdManager({
    DateTime Function()? reloj,
    this.frecuenciaMinima = const Duration(hours: 4),
  }) : _reloj = reloj ?? DateTime.now;

  /// Reloj inyectable para poder controlar el tiempo en los tests.
  final DateTime Function() _reloj;

  /// Tiempo mínimo entre dos anuncios mostrados (frequency cap).
  final Duration frecuenciaMinima;

  /// Momento en que se mostró el último anuncio. `null` si nunca se mostró.
  DateTime? _ultimaVez;

  /// Si hay un anuncio precargado listo para mostrarse.
  bool _adCargado = false;

  /// El anuncio precargado (plumbing del SDK).
  AppOpenAd? _ad;

  /// True si la app estuvo en segundo plano; distingue un "resume caliente"
  /// de un arranque en frío. Solo mostramos anuncios en resume caliente.
  bool _estuvoEnPausa = false;

  /// Guarda de reentrada: true mientras un anuncio está en pantalla.
  bool _mostrando = false;

  /// Política PURA de candados. Este es el corazón testeable del gestor.
  ///
  /// Devuelve true solo si es seguro y procede mostrar el anuncio.
  bool puedeMostrar({required bool hayAlarmaSonando}) {
    if (hayAlarmaSonando) return false; // candado crítico
    if (!_estuvoEnPausa) return false; // solo en resume caliente (no cold-start)
    if (!_adCargado) return false; // no hay ad listo
    if (_mostrando) return false; // no reentrante
    final ultima = _ultimaVez;
    if (ultima != null && _reloj().difference(ultima) < frecuenciaMinima) {
      return false; // frequency cap
    }
    return true;
  }

  /// Marca que la app pasó a segundo plano (habilita el resume caliente).
  void marcarEnPausa() => _estuvoEnPausa = true;

  /// Registra que acabamos de mostrar un anuncio (reinicia el frequency cap).
  void registrarMostrado() => _ultimaVez = _reloj();

  /// Setter de test para simular que hay (o no) un anuncio precargado.
  @visibleForTesting
  void debugSetAdCargado(bool v) => _adCargado = v;

  /// Setter de test para simular que la app estuvo (o no) en pausa.
  @visibleForTesting
  void debugSetEstuvoEnPausa(bool v) => _estuvoEnPausa = v;

  // ─── Plumbing del SDK (no se prueba en unit tests) ──────────────

  /// ID del bloque de anuncios. En debug usa los IDs de test oficiales de
  /// App Open de Google; en release devuelve null hasta tener el real.
  static String? get _adUnitId {
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9257395921'
          : 'ca-app-pub-3940256099942544/5575463023';
    }
    // TODO: reemplazar con el ID de App Open de producción de AdMob.
    return null;
  }

  /// Precarga un anuncio. Solo tiene efecto en Android/iOS con un ID válido.
  void cargar() {
    if (!(Platform.isAndroid || Platform.isIOS)) return;
    final id = _adUnitId;
    if (id == null) return;

    AppOpenAd.load(
      adUnitId: id,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _adCargado = true;
        },
        onAdFailedToLoad: (error) {
          _adCargado = false;
          // code 2 = red, code 3 = sin relleno, code 0 = interno.
          unawaited(LogService.instancia.registrar(
            'AppOpenAd FALLÓ al cargar code:${error.code} msg:${error.message}',
          ));
        },
      ),
    );
  }

  /// Muestra el anuncio si (y solo si) la política lo permite.
  void mostrarSiProcede({required bool hayAlarmaSonando}) {
    if (!puedeMostrar(hayAlarmaSonando: hayAlarmaSonando)) return;
    final ad = _ad;
    if (ad == null) return;

    _mostrando = true;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _ad = null;
        _adCargado = false;
        _mostrando = false;
        cargar(); // precarga el siguiente
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _ad = null;
        _adCargado = false;
        _mostrando = false;
        unawaited(LogService.instancia.registrar(
          'AppOpenAd FALLÓ al mostrar code:${error.code} msg:${error.message}',
        ));
        cargar(); // precarga el siguiente
      },
    );
    registrarMostrado();
    ad.show();
  }

  /// Libera el anuncio pendiente.
  void dispose() {
    _ad?.dispose();
  }
}
