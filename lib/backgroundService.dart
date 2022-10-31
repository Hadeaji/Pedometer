import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_storage/get_storage.dart';
import 'package:pedometer/pedometer.dart';


Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  /// OPTIONAL, using custom notification channel id
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'geo_alarm_foreground', // id
    'Geo Alarm Foreground', // title
    description:
    'This channel is used for important notifications.', // description
    importance: Importance.max, // importance must be at low or higher level
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  if (Platform.isIOS) {
    await flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        iOS: IOSInitializationSettings(),
      ),
    );
  }

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      // this will be executed when app is in foreground or background in separated isolate
      onStart: onStart,

      // auto start service
      autoStart: false,
      isForegroundMode: true,

      notificationChannelId: 'geo_alarm_foreground',
      initialNotificationTitle: 'Active Alarm',
      initialNotificationContent: 'Initializing',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      // auto start service
      autoStart: false,

      // this will be executed when app is in foreground in separated isolate
      onForeground: onStart,

      // you have to enable background fetch capability on xcode project
      onBackground: onIosBackground,
    ),
  );

  // service.startService();
}

// to ensure this is executed
// run app from xcode, then from xcode menu, select Simulate Background Fetch

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Only available for flutter 3.0.0 and later
  DartPluginRegistrant.ensureInitialized();

  // For flutter prior to version 3.0.0
  // We have to register the plugin manually

  // String? sad = await preferences.getString("hello");
  // print(sad);
  // await preferences.setString("hello", "world");
  final box = GetStorage();


  /// OPTIONAL when use custom notification
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });

    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });


  // final StreamingSharedPreferences preferences = await StreamingSharedPreferences.instance;
  Stream<PedestrianStatus> pedestrianStatusStream = Pedometer.pedestrianStatusStream;
  pedestrianStatusStream
      .listen((e) => {onPedestrianStatusChanged(e, box)})
      .onError((e) => {onPedestrianStatusError(e, box)});

  Stream<StepCount> stepCountStream = Pedometer.stepCountStream;
  stepCountStream
      .listen((e) => {onStepCount(e, box)})
      .onError((e) => {onStepCountError(e, box)});

  // bring to foreground
  Timer.periodic(const Duration(seconds: 1), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {

        // print("remainingDistance");

        // await activateAlarm(preferences, stopwatch, speedTimer);

        /// OPTIONAL for use custom notification
        /// the notification id must be equals with AndroidConfiguration when you call configure() method.
        flutterLocalNotificationsPlugin.show(
          888,
          'COOL SERVICE',
          box.read('_steps'),
          const NotificationDetails(
            iOS: IOSNotificationDetails(
              badgeNumber: 888,
              subtitle: 'my_foreground',
            ),
            android: AndroidNotificationDetails(
              'my_foreground',
              'MY FOREGROUND SERVICE',
              icon: 'ic_bg_service_small',
              ongoing: true,
              playSound: false,
              enableVibration: false,
              onlyAlertOnce: true,

            ),
          ),
        );

      }
    }

    /// you can see this log in logcat
    // print('FLUTTER BACKGROUND SERVICE: ${DateTime.now()}');

    // test using external plugin
    final deviceInfo = DeviceInfoPlugin();
    String? device;
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      device = androidInfo.model;
    }

    if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      device = iosInfo.model;
    }

    service.invoke(
      'update',
      {
        "current_date": DateTime.now().toIso8601String(),
        "device": device,
      },
    );
  });

  // Timer.periodic(const Duration(seconds: 3), (timer) async {
  //
  //   print('sad');
  // });
}

void onStepCount(StepCount event,GetStorage box) {
  print(event);
  box.write('_steps', event.steps.toString());
}

void onPedestrianStatusChanged(PedestrianStatus event, GetStorage box) {
  print(event);
  box.write('_status', event.status);

}

void onPedestrianStatusError(error, GetStorage box) {
  print('onPedestrianStatusError: $error');
  box.write('_status', "Pedestrian Status not available");
}

void onStepCountError(error, GetStorage box) {
  print('onStepCountError: $error');
  box.write('_steps', "Step Count not available");
}