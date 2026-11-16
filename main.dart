import 'package:flutter/material.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';

import 'spike_page.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // اختبار 7: منع تشغيل نسخة ثانية (النسخة الثانية تُظهر النافذة الأولى ثم تُغلق نفسها).
  await WindowsSingleInstance.ensureSingleInstance(
    args,
    'wirdan_spike_single_instance',
    onSecondWindow: (secondArgs) async {
      await windowManager.show();
      await windowManager.focus();
    },
  );

  await windowManager.ensureInitialized();
  final startMinimized = args.contains('--minimized');

  const options = WindowOptions(
    size: Size(980, 780),
    minimumSize: Size(720, 600),
    center: true,
    title: 'WIRDAN — اختبار الجدوى',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (startMinimized) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  // زر X لا يُنهي البرنامج؛ يخفيه إلى System Tray (يُعالَج في SpikePage).
  await windowManager.setPreventClose(true);

  await localNotifier.setup(
    appName: 'WIRDAN',
    shortcutPolicy: ShortcutPolicy.requireCreate,
  );

  runApp(const SpikeApp());
}

class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WIRDAN Spike',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E3A2B)),
      ),
      // الواجهة عربية RTL.
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const SpikePage(),
    );
  }
}
