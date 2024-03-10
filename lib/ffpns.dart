library ffpns;

import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

// @pragma('vm:entry-point')
// onBackgroundNotificationClicked(NotificationResponse details) {
//   debugPrint(" (===== [onBackgroundNotificationClicked] =====)");
//   debugPrint(details.payload);
//   try {
//     if (details.payload != null && details.payload!.isNotEmpty) {
//       Map payload = jsonDecode(details.payload.toString()) as Map;
//       debugPrint('The Payload is => $payload');
//     }
//   } catch (e) {
//     debugPrint(
//         "FFPNS::initLocalNotifs::onBackgroundNotificationClicked ERROR => $e");
//   }
//   return;
// }

@pragma('vm:entry-point')
Future<void> backgroundNotificationHandler(
  RemoteMessage message,
) async {
  debugPrint(' (-------------- [onBackgroundMessage] --------------) ');
  debugPrint(' Received Background Message: ${message.data}');
}

enum FFPNSNotificationEventType {
  foreground,
  background,
  instantiated,
}

class FFPNSOptions {
  Future<void> Function(String)? onDeviceTokenReceived;
  Map<String, String>? fcmServiceAccountCredentials;
  Function(Map, FFPNSNotificationEventType)? onNotificationClicked;
  Future<bool> Function(dynamic)? shouldBlockForegroundNotification;

  FFPNSOptions({
    this.onDeviceTokenReceived,
    this.fcmServiceAccountCredentials,
    this.onNotificationClicked,
    this.shouldBlockForegroundNotification,
  });
}

class FFPNS {
  static final instance = FFPNS();
  static final flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  //Instance-Level Variables
  String? deviceToken;
  FFPNSOptions? options;

  static initialize({
    FFPNSOptions? options,
  }) async {
    instance.options = options; //Set the instance options
    final rm = await FirebaseMessaging.instance.getInitialMessage();
    start();
    if (rm != null) {
      final pdata = rm.data['payload'];
      if (pdata == null) return;
      if (pdata!.isEmpty) return;
      Map payload = jsonDecode(pdata) as Map;
      if (instance.options?.onNotificationClicked != null) {
        instance.options!.onNotificationClicked!(
          payload,
          FFPNSNotificationEventType.instantiated,
        );
      }
    }
  }

  static start() async {
    debugPrint("FlutterFirebasePushNotificationService(FFPNS) has started");
    FirebaseMessaging.onBackgroundMessage(backgroundNotificationHandler);
    await instance.requestPermission();
    await instance.getToken();
    await instance.initLocalNotifs();
    await instance.startListeningToNotifications();
    instance.startBackgroundMessageListener();
  }

  @pragma('vm:entry-point')
  startBackgroundMessageListener() {
    debugPrint("FFPNS:BackgroundMessageListener started");
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage event) async {
      final pdata = event.data['payload'];
      if (pdata == null) return;
      if (pdata!.isEmpty) return;
      Map payload = jsonDecode(pdata) as Map;
      if (instance.options?.onNotificationClicked != null) {
        instance.options!.onNotificationClicked!(
          payload,
          FFPNSNotificationEventType.background,
        );
      }
    });
  }

  requestPermission() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint("User Granted Notification Permission");
    } else if (settings.authorizationStatus ==
        AuthorizationStatus.provisional) {
      debugPrint('User granted Proivisional Notification Permission');
    } else {
      debugPrint('User has declined or not accepted permission');
    }
  }

  getToken() async {
    print('getting token');
    final fcmToken = await FirebaseMessaging.instance.getToken();
    if (fcmToken == null) {
      debugPrint('Could not fetch FCMToken');
      return;
    }
    instance.deviceToken = fcmToken;
    if (instance.options?.onDeviceTokenReceived == null) {
      print('FFPNS::getToken: nocallback');
      return;
    }
    instance.options?.onDeviceTokenReceived!(fcmToken);
  }

  initLocalNotifs() async {
    const androidInitialize =
        AndroidInitializationSettings('@drawable/ic_notif');
    const iosInitialize = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: androidInitialize,
      iOS: iosInitialize,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        try {
          if (details.payload != null && details.payload!.isNotEmpty) {
            final pdata = details.payload;
            if (pdata == null) return;
            if (pdata.isEmpty) return;

            Map payload = jsonDecode(pdata) as Map;
            if (instance.options?.onNotificationClicked != null) {
              instance.options!.onNotificationClicked!(
                payload,
                FFPNSNotificationEventType.foreground,
              );
            }
          }
        } catch (e) {
          debugPrint(
              "FFPNS::initLocalNotifs::onDidReceiveNotificationResponse ERROR => $e");
        }
        return;
      },
    );
  }

  startListeningToNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage remoteMessage) async {
      RemoteNotification? rn = remoteMessage.notification;
      if (rn == null) {
        debugPrint('Null Remote Notification Received');
        return;
      }
      debugPrint(' (-------------- [onMessage] --------------) ');
      String? notificationTitle = rn.title;
      String? notificationBody = rn.body;

      final payload = remoteMessage.data['payload'];

      //ForegroundNotificationBlocker
      if (instance.options?.shouldBlockForegroundNotification != null) {
        final shouldBlockNotification = await instance.options
            ?.shouldBlockForegroundNotification!(jsonDecode(payload ?? '{}'));
        if (shouldBlockNotification!) {
          debugPrint('NotificationBlocked');
          return;
        }
      }

      debugPrint(
          "Received Notification: [ $notificationTitle => $notificationBody ]");
      final btsInformation = BigTextStyleInformation(
        rn.body!,
        htmlFormatBigText: true,
        contentTitle: notificationTitle,
        htmlFormatContentTitle: true,
      );
      final androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'ffpns-crezam',
        'ffpns-crezam',
        importance: Importance.high,
        styleInformation: btsInformation,
        priority: Priority.high,
        playSound: false,
      );
      final platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: const DarwinNotificationDetails(),
      );

      //Foreground setting for iOS
      FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        sound: true,
        badge: true,
      );

      await flutterLocalNotificationsPlugin.show(
        rn.hashCode,
        notificationTitle,
        notificationBody,
        platformChannelSpecifics,
        payload: payload,
      );
    });
  }

  Future<Map> sendPushNotification({
    required String title,
    required String message,
    Map? payload,
    String? receiverDeviceToken,
  }) async {
    debugPrint("Attempting to send Push Notification");
    final creds = instance.options?.fcmServiceAccountCredentials;
    if (creds == null) {
      debugPrint(
          'Cannot Send Push Notification from FFPNS without service account credentials!');
      return {
        'code': 0,
        'message':
            'Cannot Send Push Notification from FFPNS without service account credentials!',
      };
    }
    Future<String?> generateAuthorizationToken() async {
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final accountCredentials = ServiceAccountCredentials.fromJson(creds);
      final client = http.Client();
      AccessCredentials credentials;
      try {
        credentials = await obtainAccessCredentialsViaServiceAccount(
          accountCredentials,
          scopes,
          client,
        );
      } catch (e) {
        debugPrint(
            'FFPNS::sendPushNotification::generateAuthorizationToken EXCEPTION => $e');
        return null;
      }
      client.close();
      return credentials.accessToken.data;
    }

    String? fpid = creds['project_id'];
    String? accessToken = await generateAuthorizationToken();
    if (accessToken == null) {
      debugPrint('Cannot send Push Notification. AccessToken cannot be null.');
      return {
        'code': 0,
        'message': 'Cannot send Push Notification. AccessToken cannot be null.',
      };
    }
    try {
      String receiverToken = receiverDeviceToken ?? instance.deviceToken!;

      Map pushNotificationBody = {
        'message': {
          'token': receiverToken,
          'notification': {
            'body': message,
            'title': title,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'ffpns-crezam',
            },
          },
          'apns': {
            'payload': {
              'aps': {
                'alert': {
                  'body': message,
                  'title': title,
                }
              }
            }
          },
          if (payload != null)
            'data': {
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              'status': 'done',
              'payload': jsonEncode(payload),
              'title': title,
            },
        }
      };
      final res = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$fpid/messages:send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(pushNotificationBody),
      );
      print(res.body);
      debugPrint(
          'CODE: ${res.statusCode} | Push Notification Sent to $receiverToken!');
      return {
        'code': res.statusCode,
        'message': res.body.toString(),
      };
    } catch (e) {
      debugPrint("FFPNS::sendPushNotification => ERROR: $e");
      return {
        'code': 0,
        'message': 'FFPNS::sendPushNotification => ERROR: $e',
      };
    }
  }
}
