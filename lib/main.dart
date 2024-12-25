import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:logging/logging.dart';
import 'package:permission_handler/permission_handler.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request permissions before initializing services
  await [
    Permission.notification,
    Permission.storage,
  ].request();

  await initializeService();
  await initializeNotifications();
  runApp(const MyApp());
}

@pragma('vm:entry-point')
Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  // Create notification channel
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'timer_channel',
    'Timer Service',
    description: 'Timer app background service',
    importance: Importance.high,
    playSound: false,
    enableVibration: true,
    showBadge: true,
    enableLights: true,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: false,
      notificationChannelId: 'timer_channel',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );

  await service.startService();
}

Future<void> initializeNotifications() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'timer_channel',
    'Timer Notifications',
    description: 'Timer completion notifications',
    importance: Importance.max,
    playSound: false,
    enableVibration: true,
    showBadge: true,
    enableLights: true,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) async {
      // 노티피케이션 응답 핸들러 제거 - 알람을 자동으로 중지하지 않도록 함
    },
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final alarmPlayer = AlarmPlayer();
  alarmPlayer.initialize();

  Timer? backgroundTimer;

  service.on('startTimer').listen((event) {
    if (event != null) {
      final duration = event['duration'] as int;
      if (duration > 0) {
        // 기존 타이머가 있다면 취소
        backgroundTimer?.cancel();

        // 새로운 타이머 시작
        backgroundTimer =
            Timer.periodic(const Duration(seconds: 1), (timer) async {
          if (duration <= 0) {
            timer.cancel();
            String soundPath = event['sound'] as String? ?? 'sounds/alarm1.mp3';
            // Extract only the filename if a full path is provided
            String cleanPath = soundPath.split('/').last;
            if (!cleanPath.endsWith('.mp3')) {
              cleanPath = 'sounds/$cleanPath.mp3';
            } else if (!soundPath.startsWith('sounds/')) {
              cleanPath = 'sounds/$cleanPath';
            } else {
              cleanPath = soundPath;
            }
            print('Playing sound with path: $cleanPath'); // Debug log
            await alarmPlayer.playAlarm(cleanPath);

            // 타이머 완료 시 알림 표시
            await flutterLocalNotificationsPlugin.show(
              0,
              '타이머 종료',
              '타이머가 완료되었습니다.',
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'timer_notification',
                  'Timer Notifications',
                  channelDescription: 'Notification channel for timer',
                  importance: Importance.max,
                  priority: Priority.high,
                  playSound: false,
                  enableVibration: true,
                  ongoing: true,
                  autoCancel: false,
                ),
              ),
            );
          }
        });
      }
    }
  });

  service.on('stopAlarm').listen((event) async {
    backgroundTimer?.cancel();
    await alarmPlayer.stopAlarm();
    await flutterLocalNotificationsPlugin.cancel(0);
  });

  service.on('stopService').listen((event) {
    backgroundTimer?.cancel();
    service.stopSelf();
  });
}

class AlarmPlayer {
  static final AlarmPlayer _instance = AlarmPlayer._internal();
  factory AlarmPlayer() => _instance;
  AlarmPlayer._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isAlarmPlaying = false;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (!_isInitialized) {
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      _isInitialized = true;
    }
  }

  Future<void> playAlarm(String soundFile) async {
    if (!_isInitialized) {
      print('Initializing audio player...');
      await initialize();
    }
    if (!_isAlarmPlaying) {
      try {
        print('Original soundFile path: $soundFile');
        // Remove 'assets/' if it exists in the path
        String cleanPath = soundFile.startsWith('assets/')
            ? soundFile.substring(7)
            : soundFile;
        print('Cleaned path: $cleanPath');

        // Extract just the filename for debugging
        String filename = cleanPath.split('/').last;
        print('Attempting to play file: $filename');

        print('Setting audio source...');
        final source = AssetSource(cleanPath);
        print('Created AssetSource with path: ${source.path}');
        
        await _audioPlayer.setSource(source);
        print('Source set successfully');
        
        print('Setting volume to maximum...');
        await _audioPlayer.setVolume(1.0);
        
        print('Starting playback...');
        await _audioPlayer.resume();
        _isAlarmPlaying = true;
        print('Successfully started playing: $cleanPath');
      } catch (e) {
        print('Error playing alarm: $e');
        print('Stack trace: ${StackTrace.current}');
        print('Failed to play file: $soundFile');
      }
    } else {
      print('Alarm is already playing');
    }
  }

  Future<void> stopAlarm() async {
    if (_isAlarmPlaying) {
      try {
        print('Stopping alarm...');
        await _audioPlayer.pause();
        await _audioPlayer.seek(Duration.zero);
        _isAlarmPlaying = false;
        print('Alarm stopped successfully');
      } catch (e) {
        print('Error stopping alarm: $e');
      }
    }
  }

  bool get isAlarmPlaying => _isAlarmPlaying;
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Timer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: const TimerPage(),
    );
  }
}

class TimerPage extends StatefulWidget {
  const TimerPage({Key? key}) : super(key: key);

  @override
  _TimerPageState createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {
  Timer? _timer;
  int _timeInSeconds = 0;
  int _selectedTime = 15 * 60;
  bool _isRunning = false;
  late SharedPreferences _prefs;
  List<int> _timePresets = [15, 30, 45, 60];
  List<String> _soundPresets = [
    'sounds/alarm1.mp3',
    'sounds/alarm2.mp3',
    'sounds/alarm3.mp3',
    'sounds/alarm4.mp3'
  ];
  int _currentPresetIndex = 0;
  bool _isDialogShowing = false;

  void _closeDialog(BuildContext dialogContext) {
    Navigator.of(dialogContext).pop(); // Use the dialog's context to pop
    setState(() {
      _isDialogShowing = false;
    });
  }

  Future<bool> _stopAlarmAndNotification() async {
    if (!_isRunning) return true; // Prevent repeated stopping
    final service = FlutterBackgroundService();
    service.invoke('stopAlarm', {}); // Remove await since invoke returns void
    await flutterLocalNotificationsPlugin.cancelAll();
    AlarmPlayer().stopAlarm();
    _isRunning = false; // Ensure running state is false
    print('Alarm and notifications stopped'); // Debug log
    return true; // Allow pop
  }

  @override
  void initState() {
    super.initState();
    _initPrefs();
    WidgetsBinding.instance.addObserver(this);
    _setupNotificationChannel();

    print('Current sound presets: $_soundPresets'); // 디버그 로그 추가

    // 백그라운드 서비스의 시간 업데이트 수신
    FlutterBackgroundService().on('updateTime').listen((event) {
      if (!mounted) return;
      if (event != null && event['timeInSeconds'] != null) {
        setState(() {
          _timeInSeconds = int.parse(event['timeInSeconds'].toString());
          _saveState();
        });
      }
    });

    // 타이머 종료 이벤트 수신
    FlutterBackgroundService().on('timerCompleted').listen((event) async {
      if (!mounted) return;
      await _checkAndShowStopAlarmDialog();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    AlarmPlayer().stopAlarm();
    final service = FlutterBackgroundService();
    service.invoke('stopAlarm', {});
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 백그라운드로 갈 때는 상태만 저장
      _saveState();

      // 타이머가 실행 중이면 백그라운드 서비스 시작
      if (_isRunning) {
        final service = FlutterBackgroundService();
        String soundPath = _soundPresets[_currentPresetIndex];
        print('Starting timer with sound: $soundPath'); // Debug log
        service.invoke(
          'startTimer',
          {
            'duration': _timeInSeconds,
            'sound': soundPath,
          },
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      _loadSavedState();
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadSavedState();
    _loadTimePresets();
  }

  void _loadTimePresets() {
    setState(() {
      _timePresets =
          _prefs.getStringList('timePresets')?.map(int.parse).toList() ??
              [15, 30, 45, 60];
      _soundPresets = _prefs.getStringList('soundPresets') ??
          List.filled(4, 'sounds/alarm1.mp3');
    });
  }

  Future<void> _checkAndShowStopAlarmDialog() async {
    if (!mounted || _isDialogShowing) {
      print('Dialog is already showing or widget not mounted');
      return;
    }

    setState(() {
      _isDialogShowing = true;
    });

    try {
      Navigator.of(context).popUntil((route) => route.isFirst);

      if (!mounted) return; // Check mounted again after potential route changes

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return WillPopScope(
            onWillPop: () async {
              return await _stopAlarmAndNotification(); // Use await to get the boolean return value
            },
            child: AlertDialog(
              title: const Text('타이머 종료'),
              content: const Text('타이머가 완료되었습니다.\n알람을 종료하시겠습니까?'),
              actions: <Widget>[
                TextButton(
                  child: const Text('종료'),
                  onPressed: () async {
                    await _stopAlarmAndNotification();
                    if (mounted && _isDialogShowing) {
                      // Check both mounted and dialog state
                      _closeDialog(dialogContext);
                    }
                  },
                ),
              ],
            ),
          );
        },
      ).whenComplete(() {
        if (mounted) {
          setState(() {
            _isDialogShowing = false;
          });
        }
      });
    } catch (e) {
      print('Error showing dialog: $e');
      if (mounted) {
        setState(() {
          _isDialogShowing = false;
        });
      }
    }
  }

  Future<void> _repeatAlarmAndNotification() async {
    while (true) {
      // 지속적으로 반복
      if (!_isRunning) break; // 타이머가 중지되면 반복 종료
      await _showNotification('타이머 완료', '타이머가 완료되었습니다. 알람이 반복됩니다.');
      await Future.delayed(Duration(minutes: 1)); // 1분마다 알람 반복
    }
  }

  Future<void> _saveState() async {
    await _prefs.setInt('timeInSeconds', _timeInSeconds);
    await _prefs.setInt('selectedTime', _selectedTime);
    await _prefs.setBool('isRunning', _isRunning);
    await _prefs.setInt('currentPresetIndex', _currentPresetIndex);
  }

  void _loadSavedState() {
    setState(() {
      _timeInSeconds = _prefs.getInt('timeInSeconds') ?? _selectedTime;
      _selectedTime = _prefs.getInt('selectedTime') ?? 15 * 60;
      _isRunning = _prefs.getBool('isRunning') ?? false;
      _currentPresetIndex = _prefs.getInt('currentPresetIndex') ?? 0;
      if (_isRunning) {
        _startTimer();
      }
    });
  }

  void _startTimer() {
    if (_isRunning) return; // Prevent repeated starting
    _timeInSeconds = _timeInSeconds > 0 ? _timeInSeconds : _selectedTime;
    _isRunning = true;
    _saveState();

    final service = FlutterBackgroundService();
    String soundPath = _soundPresets[_currentPresetIndex];
    print('Starting timer with sound: $soundPath'); // Debug log
    service.invoke(
      'startTimer',
      {
        'duration': _timeInSeconds,
        'sound': soundPath,
      },
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted) return;
      setState(() {
        if (_timeInSeconds > 0) {
          _timeInSeconds--;
          _saveState();
        } else {
          _repeatAlarmAndNotification(); // 타이머 완료 시 알람 반복
          _stopTimer();
        }
      });
    });
  }

  Future<void> _stopTimer() async {
    setState(() {
      _timer?.cancel();
      _isRunning = false;
      _saveState();
    });

    await _showStopAlarmDialog();
  }

  Future<void> _showStopAlarmDialog() async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return WillPopScope(
          onWillPop: () async => false, // 뒤로 가기 버튼 비활성화
          child: AlertDialog(
            title: const Text('타이머 종료'),
            content: const Text('타이머가 완료되었습니다.\n알람을 종료하시겠습니까?'),
            actions: <Widget>[
              TextButton(
                child: const Text('종료'),
                onPressed: () async {
                  try {
                    // 백그라운드 서비스에 알람 중지 요청
                    final service = FlutterBackgroundService();
                    service.invoke('stopAlarm', {});

                    // 알람 중지
                    await AlarmPlayer().stopAlarm();

                    // 알림 제거
                    await flutterLocalNotificationsPlugin.cancel(0);

                    // 다이얼로그 닫기
                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                  } catch (e) {
                    print('Error stopping alarm: $e');
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _resetTimer() {
    setState(() {
      _timer?.cancel();
      _timeInSeconds = _selectedTime;
      _isRunning = false;
      _saveState();
    });
  }

  void _addTime(int seconds) {
    setState(() {
      if (!_isRunning) {
        _currentPresetIndex = _timePresets.indexOf(seconds);
        _selectedTime = seconds;
        _timeInSeconds = _selectedTime;
      } else {
        _timeInSeconds += seconds;
        _selectedTime = _timeInSeconds;
      }
      _saveState();
    });
  }

  Future<void> _showNotification(String title, String body) async {
    try {
      String selectedSound = _soundPresets[_currentPresetIndex];
      await AlarmPlayer().playAlarm(selectedSound);

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'timer_notification',
        'Timer Notifications',
        channelDescription: 'Notification channel for timer',
        importance: Importance.max,
        priority: Priority.high,
        sound: null,
        playSound: false,
        enableVibration: true,
        ongoing: true,
        autoCancel: false,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'stop_alarm',
            '알림음 중지',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      );

      const NotificationDetails platformChannelSpecifics =
          NotificationDetails(android: androidPlatformChannelSpecifics);

      await flutterLocalNotificationsPlugin.show(
        0,
        title,
        body,
        platformChannelSpecifics,
        payload: 'timer_completed',
      );
    } catch (e, stackTrace) {
      final logger = Logger('TimerNotification');
      logger.severe('Error playing audio: $e', e, stackTrace);
    }
  }

  Future<void> _setupNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'timer_notification',
      'Timer Notifications',
      description: 'Notification channel for timer',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  String _formatTime(int timeInSeconds) {
    int minutes = timeInSeconds ~/ 60;
    int seconds = timeInSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsPage(),
      ),
    );

    // 설정이 변경되었다면 상태 업데이트
    if (result != null && mounted) {
      setState(() {
        _timePresets = (result['timePresets'] as List<int>);
        _soundPresets = (result['soundPresets'] as List<String>);
        // 현재 선택된 시간도 업데이트
        _selectedTime = _timePresets[_currentPresetIndex];
        if (!_isRunning) {
          _timeInSeconds = _selectedTime;
        }
      });
      // 설정이 변경되었으므로 상태 저장
      _saveState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Easy Timer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 300,
                    height: 300,
                    child: TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      tween: Tween<double>(
                        begin: _timeInSeconds / _selectedTime,
                        end: _timeInSeconds / _selectedTime,
                      ),
                      builder: (context, value, _) => CircularProgressIndicator(
                        value: value.clamp(0.0, 1.0),
                        strokeWidth: 12,
                        backgroundColor: Colors.grey[800],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isRunning ? Colors.blue : Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(_timeInSeconds),
                        style: const TextStyle(
                          fontSize: 72,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_isRunning)
                        Text(
                          'Remaining',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[400],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: _timePresets
                      .map((minutes) => _buildTimeButton(minutes))
                      .toList(),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(bottom: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: Icons.refresh,
                      onPressed: _resetTimer,
                      label: 'Reset',
                    ),
                    _buildMainButton(),
                    _buildControlButton(
                      icon: Icons.stop,
                      onPressed: _stopTimer,
                      label: 'Stop',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon),
          onPressed: onPressed,
          iconSize: 32,
          color: Colors.white,
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildMainButton() {
    return GestureDetector(
      onTap: _isRunning ? _stopTimer : _startTimer,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRunning ? Colors.red : Colors.green,
        ),
        child: Icon(
          _isRunning ? Icons.pause : Icons.play_arrow,
          size: 40,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTimeButton(int seconds) {
    final bool isSelected = _selectedTime == seconds;
    String buttonText;
    if (seconds >= 60) {
      buttonText = '${seconds ~/ 60}m ${seconds % 60}s';
    } else {
      buttonText = '${seconds}s';
    }

    return ElevatedButton(
      onPressed: () => _addTime(seconds),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue : Colors.grey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: Text(
        buttonText,
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}
