import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const int kSyncAlertNotificationId = 1001;
const Duration kSyncAlertInterval = Duration(minutes: 10);

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _initFailed = false;

  // flutter_local_notifications 17.x n'enregistre pas d'implémentation
  // Windows/Linux. Sans ce garde-fou, initialize() peut sembler réussir puis
  // périodiquementShow() lève une LateInitializationError sur ces plateformes.
  bool get _isSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Initialise le plugin. Retourne true si l'initialisation a réussi.
  Future<bool> init() async {
    if (_initialized) return true;
    if (_initFailed) return false; // évite les tentatives répétées
    if (!_isSupportedPlatform) {
      _initFailed = true;
      return false;
    }

    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      final result = await _plugin.initialize(settings);
      if (result == false) {
        _initFailed = true;
        if (kDebugMode) {
          debugPrint('NotificationService : initialize() a retourné false.');
        }
        return false;
      }

      _initialized = true;
      return true;
    } catch (e, st) {
      _initFailed = true;
      if (kDebugMode) {
        debugPrint('NotificationService.init() error: $e\n$st');
      }
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return true;
    if (!_initialized) return false;

    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return (await android?.requestNotificationsPermission()) ?? false;
    }
    if (Platform.isIOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return (await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          )) ??
          false;
    }
    return true;
  }

  NotificationDetails _alertDetails() {
    const android = AndroidNotificationDetails(
      'sync_alert_channel',
      'Alerte de synchronisation',
      channelDescription:
          'Rappelle la nécessité de sauvegarder les données locales.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alert'),
      enableVibration: true,
      ongoing: true,
      icon: '@mipmap/ic_launcher', // icône explicite (voir correctif 2)
    );
    const darwin = DarwinNotificationDetails(
      presentSound: true,
      sound: 'alert.mp3',
      presentAlert: true,
      presentBadge: true,
    );
    return const NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
  }

  /// Tente de démarrer l'alerte. Ne fait rien si l'init a échoué.
  Future<void> startSyncAlert({required int pendingCount}) async {
    if (!await init()) return; // sécurité
    try {
      await _plugin.periodicallyShowWithDuration(
        kSyncAlertNotificationId,
        'Synchronisation requise',
        '$pendingCount modifications en attente. '
            'Synchronisez avec le serveur pour sauvegarder vos données.',
        kSyncAlertInterval,
        _alertDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('NotificationService.startSyncAlert error: $e\n$st');
      }
    }
  }

  Future<void> stopSyncAlert() async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(kSyncAlertNotificationId);
    } catch (_) {}
  }

  Future<bool> isSyncAlertActive() async {
    if (!_initialized) return false;
    final pending = await _plugin.pendingNotificationRequests();
    return pending.any((r) => r.id == kSyncAlertNotificationId);
  }
}
