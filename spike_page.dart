import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart' hide MenuItem;
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'spike_db.dart';

/// اسم قيمة التشغيل التلقائي في سجل Windows (يحذفها المثبّت عند الإزالة).
const _startupName = 'WIRDAN Spike';

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage>
    with WindowListener, TrayListener {
  final AudioPlayer _player = AudioPlayer();
  final SpikeDb _db = SpikeDb();
  final List<String> _logs = [];
  // نحتفظ بمراجع الإشعارات كي لا تُحذف ردود أفعالها (زر «إيقاف الصوت»).
  final List<LocalNotification> _notifications = [];

  final Map<String, bool> _results = {
    'installer': false,
    'toast': false,
    'audio': false,
    'tray': false,
    'db': false,
    'startup': false,
    'single': false,
  };

  bool _playing = false;
  bool _startupEnabled = false;
  int _countdown = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);
    _init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    _countdownTimer?.cancel();
    _player.dispose();
    _db.close();
    super.dispose();
  }

  // ---------------------------------------------------------------- سجل
  void _log(String message) {
    final t = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$t] $message';
    if (mounted) {
      setState(() => _logs.add(line));
    } else {
      _logs.add(line);
    }
  }

  // ------------------------------------------------------------ تهيئة
  Future<void> _init() async {
    _log('Windows: ${Platform.operatingSystemVersion}');
    _log('Dart: ${Platform.version.split(' ').first}');
    _log('Exe: ${Platform.resolvedExecutable}');

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });

    // System Tray
    try {
      await trayManager.setIcon('assets/tray_icon.ico');
      await trayManager.setToolTip('WIRDAN — اختبار الجدوى');
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: 'فتح النافذة'),
        MenuItem(key: 'stop_sound', label: 'إيقاف الصوت'),
        MenuItem.separator(),
        MenuItem(key: 'exit', label: 'خروج كامل'),
      ]));
      _log('Tray: أُنشئت الأيقونة');
    } catch (e) {
      _log('Tray FAILED: $e');
    }

    // التشغيل التلقائي مع Windows
    try {
      launchAtStartup.setup(
        appName: _startupName,
        appPath: Platform.resolvedExecutable,
        args: const ['--minimized'],
      );
      _startupEnabled = await launchAtStartup.isEnabled();
      _log('Startup: الحالة الحالية = ${_startupEnabled ? "مفعّل" : "معطّل"}');
    } catch (e) {
      _log('Startup FAILED: $e');
    }

    // قاعدة البيانات: نقرأ ما خُزّن في تشغيل سابق (اختبار الاستمرارية)
    try {
      final rows = await _db.select(_db.spikeEntries).get();
      _log('DB: تعمل، السجلات المخزّنة من قبل = ${rows.length}');
    } catch (e) {
      _log('DB FAILED: $e');
    }

    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------- Tray
  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showWindow();
        break;
      case 'stop_sound':
        _stopTone();
        break;
      case 'exit':
        _exitApp();
        break;
    }
  }

  // ------------------------------------------------------------- النافذة
  @override
  void onWindowClose() async {
    final prevent = await windowManager.isPreventClose();
    if (prevent) {
      await windowManager.hide();
      _log('زر X: أُخفيت النافذة إلى Tray (البرنامج ما زال يعمل)');
    }
  }

  Future<void> _exitApp() async {
    await _player.stop();
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // --------------------------------------------------------------- الصوت
  Future<void> _playTone() async {
    try {
      // نكرّر النغمة لمحاكاة أذان طويل، فيظهر دور زر «إيقاف» فعلياً.
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/test_tone.wav'));
      _log('Audio: بدأ التشغيل');
    } catch (e) {
      _log('Audio FAILED: $e');
    }
  }

  Future<void> _stopTone() async {
    try {
      await _player.stop();
      _log('Audio: أُوقف الصوت');
    } catch (e) {
      _log('Audio stop FAILED: $e');
    }
  }

  // ------------------------------------------------------------ الإشعار
  Future<void> _showNotification(
      {String title = 'WIRDAN — إشعار تجريبي',
      String body = 'إن ظهر هذا الإشعار فالإشعارات تعمل.'}) async {
    try {
      final n = LocalNotification(
        title: title,
        body: body,
        actions: [LocalNotificationAction(text: 'إيقاف الصوت')],
      );
      n.onShow = () => _log('Toast: ظهر الإشعار');
      n.onClick = () => _log('Toast: نُقر على الإشعار');
      n.onClickAction = (index) {
        _log('Toast: نُقر زر الإجراء رقم $index → إيقاف الصوت');
        _stopTone();
      };
      n.onClose = (reason) => _log('Toast: أُغلق ($reason)');
      _notifications.add(n);
      await n.show();
    } catch (e) {
      _log('Toast FAILED: $e');
    }
  }

  /// اختبار الخلفية: بعد 10 ثوانٍ يصدر إشعار وصوت، حتى لو أخفيتَ النافذة.
  void _startDelayedTest() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 10);
    _log('اختبار الخلفية: سيصدر إشعار وصوت بعد 10 ثوانٍ. أخفِ النافذة بزر X الآن.');
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        timer.cancel();
        _log('اختبار الخلفية: حان الوقت');
        await _playTone();
        await _showNotification(
          title: 'حان وقت الاختبار',
          body: 'يجب أن تسمع النغمة الآن. اضغط «إيقاف الصوت».',
        );
      }
    });
  }

  // ------------------------------------------------------- قاعدة البيانات
  Future<void> _dbTest() async {
    try {
      await _db.into(_db.spikeEntries).insert(
            SpikeEntriesCompanion.insert(note: 'تجربة ${DateTime.now()}'),
          );
      final rows = await _db.select(_db.spikeEntries).get();
      _log('DB: كتابة وقراءة ناجحتان، عدد السجلات الآن = ${rows.length}');
    } catch (e) {
      _log('DB FAILED: $e');
    }
  }

  // ------------------------------------------------------ التشغيل التلقائي
  Future<void> _toggleStartup(bool value) async {
    try {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      final enabled = await launchAtStartup.isEnabled();
      setState(() => _startupEnabled = enabled);
      _log('Startup: أصبح ${enabled ? "مفعّلاً" : "معطّلاً"}');
    } catch (e) {
      _log('Startup FAILED: $e');
    }
  }

  // --------------------------------------------------------------- تقرير
  String _buildReport() {
    const names = {
      'installer': '1) التثبيت والتشغيل كبرنامج عادي',
      'toast': '2) الإشعار وزر «إيقاف الصوت»',
      'audio': '3) تشغيل الصوت وإيقافه',
      'tray': '4) System Tray وزر X',
      'db': '5) قاعدة البيانات (واستمرارها بعد إعادة التشغيل)',
      'startup': '6) التشغيل مع Windows',
      'single': '7) منع النسخة الثانية',
    };
    final b = StringBuffer('تقرير اختبار الجدوى — WIRDAN Spike\n\n');
    _results.forEach((k, v) => b.writeln('[${v ? "x" : " "}] ${names[k]}'));
    b.writeln('\n--- السجل ---');
    b.writeln(_logs.join('\n'));
    return b.toString();
  }

  Future<void> _copyReport() async {
    await Clipboard.setData(ClipboardData(text: _buildReport()));
    _log('نُسخ التقرير إلى الحافظة. الصقه في المحادثة.');
  }

  // ----------------------------------------------------------------- واجهة
  Widget _section({
    required String resultKey,
    required String title,
    required String instructions,
    required List<Widget> actions,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const Text('نجح'),
              Checkbox(
                value: _results[resultKey],
                onChanged: (v) =>
                    setState(() => _results[resultKey] = v ?? false),
              ),
            ]),
            Text(instructions),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WIRDAN — اختبار جدوى المكتبات')),
      body: Column(
        children: [
          // زر الإيقاف متاح دائماً أثناء تشغيل الصوت.
          if (_playing)
            Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.all(10),
              child: Row(children: [
                const Icon(Icons.volume_up, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('الصوت يعمل الآن',
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
                FilledButton(
                  onPressed: _stopTone,
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red.shade800),
                  child: const Text('إيقاف الصوت الآن'),
                ),
              ]),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section(
                  resultKey: 'installer',
                  title: '1) التثبيت',
                  instructions:
                      'إن رأيتَ هذه الصفحة فقد ثُبّت البرنامج وفُتح دون أي أدوات تطوير. '
                      'علّم «نجح» إن ثبّتّه من WIRDAN-Spike-Setup.exe وفتحتَه من قائمة Start.',
                  actions: const [],
                ),
                _section(
                  resultKey: 'toast',
                  title: '2) الإشعار',
                  instructions:
                      'اضغط الزر. يجب أن يظهر إشعار Windows بزر «إيقاف الصوت». '
                      'جرّبه مع الصوت أيضاً (زر 3) ثم اضغط الزر داخل الإشعار.',
                  actions: [
                    FilledButton(
                        onPressed: () => _showNotification(),
                        child: const Text('إرسال إشعار')),
                  ],
                ),
                _section(
                  resultKey: 'audio',
                  title: '3) الصوت',
                  instructions:
                      'تُشغَّل نغمة تتكرر حتى تُوقفها، لتحاكي أذاناً طويلاً. '
                      'يجب أن يظهر شريط أحمر بزر «إيقاف» أثناء التشغيل.',
                  actions: [
                    FilledButton(
                        onPressed: _playTone, child: const Text('تشغيل النغمة')),
                    OutlinedButton(
                        onPressed: _stopTone, child: const Text('إيقاف')),
                  ],
                ),
                _section(
                  resultKey: 'tray',
                  title: '4) System Tray والخلفية',
                  instructions:
                      'اضغط «ابدأ اختبار الخلفية» ثم أغلق النافذة بزر X فوراً. '
                      'يجب أن يبقى البرنامج في Tray، ويصدر الإشعار والصوت بعد 10 ثوانٍ. '
                      'انقر أيقونة Tray لفتح النافذة، وزر الفأرة الأيمن للقائمة (إيقاف الصوت / خروج كامل).',
                  actions: [
                    FilledButton(
                      onPressed: _startDelayedTest,
                      child: Text(_countdown > 0
                          ? 'يبدأ بعد $_countdown ثوانٍ…'
                          : 'ابدأ اختبار الخلفية'),
                    ),
                  ],
                ),
                _section(
                  resultKey: 'db',
                  title: '5) قاعدة البيانات',
                  instructions:
                      'اضغط الزر عدة مرات. ثم اخرج خروجاً كاملاً وأعد فتح البرنامج: '
                      'يجب أن يذكر السجل «السجلات المخزّنة من قبل» بعدد أكبر من صفر.',
                  actions: [
                    FilledButton(
                        onPressed: _dbTest,
                        child: const Text('كتابة وقراءة سجل')),
                  ],
                ),
                _section(
                  resultKey: 'startup',
                  title: '6) التشغيل مع Windows',
                  instructions:
                      'فعّله ثم أعد تشغيل Windows. يجب أن يبدأ البرنامج مخفياً في Tray. '
                      'ثم عطّله وتأكد أنه لا يبدأ.',
                  actions: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Switch(value: _startupEnabled, onChanged: _toggleStartup),
                      Text(_startupEnabled ? 'مفعّل' : 'معطّل'),
                    ]),
                  ],
                ),
                _section(
                  resultKey: 'single',
                  title: '7) نسخة واحدة فقط',
                  instructions:
                      'والبرنامج يعمل (حتى لو مخفياً)، افتحه مرة ثانية من قائمة Start. '
                      'يجب ألا تظهر نسخة ثانية؛ بل تظهر هذه النافذة.',
                  actions: const [],
                ),
                const SizedBox(height: 4),
                Row(children: [
                  FilledButton.icon(
                    onPressed: _copyReport,
                    icon: const Icon(Icons.copy),
                    label: const Text('نسخ التقرير'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                      onPressed: _exitApp,
                      child: const Text('خروج كامل')),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _logs.isEmpty ? '(السجل فارغ)' : _logs.join('\n'),
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'Consolas', fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
