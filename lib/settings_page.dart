import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/cupertino.dart';
import 'dart:io';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<int> _timePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
  List<String> _soundPresets = [
    'sounds/alarm1.mp3',
    'sounds/alarm2.mp3',
    'sounds/alarm3.mp3',
    'sounds/alarm4.mp3'
  ];
  List<int> _selectedMinutes = List.filled(4, 0);
  List<int> _selectedSeconds = List.filled(4, 0);
  late SharedPreferences _prefs;
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<bool> _isPlayingList = List.filled(4, false);

  final List<String> _availableSounds = [
    'sounds/alarm1.mp3',
    'sounds/alarm2.mp3',
    'sounds/alarm3.mp3',
    'sounds/alarm4.mp3',
  ];

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _initAudioPlayer();
  }

  Future<void> _initAudioPlayer() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _loadPresets();
  }

  void _loadPresets() {
    setState(() {
      _timePresets = _prefs.getStringList('timePresets')?.map(int.parse).toList() ?? 
          [15 * 60, 30 * 60, 45 * 60, 60 * 60];
      _soundPresets = _prefs.getStringList('soundPresets') ?? List.filled(4, 'sounds/alarm1.mp3');
      
      for (int i = 0; i < _soundPresets.length; i++) {
        if (!_availableSounds.contains(_soundPresets[i])) {
          _soundPresets[i] = 'sounds/alarm1.mp3';
        }
      }
      
      for (int i = 0; i < _timePresets.length; i++) {
        int totalSeconds = _timePresets[i];
        _selectedMinutes[i] = totalSeconds ~/ 60;
        _selectedSeconds[i] = totalSeconds % 60;
      }
    });
  }

  void _resetToDefaults() {
    setState(() {
      _timePresets = [15 * 60, 30 * 60, 45 * 60, 60 * 60];
      _soundPresets = List.filled(4, 'sounds/alarm1.mp3');

      for (int i = 0; i < _timePresets.length; i++) {
        int totalSeconds = _timePresets[i];
        _selectedMinutes[i] = totalSeconds ~/ 60;
        _selectedSeconds[i] = totalSeconds % 60;
      }
    });
    _savePresets();  // 리셋된 값을 저장
  }

  Future<void> _savePresets() async {
    try {
      // 시간 프리셋 저장
      List<String> timePresetStrings = [];
      for (int i = 0; i < 4; i++) {
        int totalSeconds = _selectedMinutes[i] * 60 + _selectedSeconds[i];
        timePresetStrings.add(totalSeconds.toString());
      }
      
      // 상태 업데이트
      setState(() {
        _timePresets = timePresetStrings.map(int.parse).toList();
      });

      // SharedPreferences에 저장
      await _prefs.setStringList('timePresets', timePresetStrings);
      await _prefs.setStringList('soundPresets', _soundPresets);

      // 저장 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Center(
              child: Text(
                '설정이 저장되었습니다.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
        
        // 설정 페이지를 닫고 결과 반환
        Navigator.pop(context, {
          'timePresets': _timePresets,
          'soundPresets': _soundPresets,
        });
      }
    } catch (e) {
      // 에러 발생 시 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      print('Error saving presets: $e');
    }
  }

  Future<void> _playSound(String sound, int index) async {
    try {
      for (int i = 0; i < _isPlayingList.length; i++) {
        if (_isPlayingList[i] && i != index) {
          await _audioPlayer.stop();
          setState(() {
            _isPlayingList[i] = false;
          });
        }
      }

      if (_isPlayingList[index]) {
        await _audioPlayer.stop();
        setState(() {
          _isPlayingList[index] = false;
        });
      } else {
        // Add 'assets/' prefix for AudioPlayer
        String assetPath = 'assets/$sound';
        print('Playing sound: $assetPath');
        await _audioPlayer.play(AssetSource(sound));
        setState(() {
          _isPlayingList[index] = true;
        });
      }
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  Widget _buildTimeSelector(int index) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 분 선택 콤보박스
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Platform.isIOS
                ? CupertinoPicker.builder(
                    itemExtent: 32,
                    scrollController: FixedExtentScrollController(
                      initialItem: _selectedMinutes[index],
                    ),
                    onSelectedItemChanged: (int value) {
                      setState(() {
                        _selectedMinutes[index] = value;
                      });
                    },
                    itemBuilder: (context, index) {
                      return Center(
                        child: Text(
                          index.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    },
                    childCount: 60,
                  )
                : DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: '분',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    value: _selectedMinutes[index].clamp(0, 59),  
                    items: List.generate(
                      60,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(i.toString()),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedMinutes[index] = value;
                        });
                      }
                    },
                  ),
          ),
        ),
        Text(
          '분',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 16,
          ),
        ),
        const SizedBox(width: 16),
        // 초 선택 콤보박스
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Platform.isIOS
                ? CupertinoPicker.builder(
                    itemExtent: 32,
                    scrollController: FixedExtentScrollController(
                      initialItem: _selectedSeconds[index],
                    ),
                    onSelectedItemChanged: (int value) {
                      setState(() {
                        _selectedSeconds[index] = value;
                      });
                    },
                    itemBuilder: (context, index) {
                      return Center(
                        child: Text(
                          index.toString(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    },
                    childCount: 60,
                  )
                : DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: '초',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    value: _selectedSeconds[index].clamp(0, 59),  
                    items: List.generate(
                      60,
                      (i) => DropdownMenuItem(
                        value: i,
                        child: Text(i.toString()),
                      ),
                    ),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selectedSeconds[index] = value;
                        });
                      }
                    },
                  ),
          ),
        ),
        Text(
          '초',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildSoundSelector(int index) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            child: Platform.isIOS
                ? CupertinoPicker(
                    backgroundColor: Colors.transparent,
                    itemExtent: 32.0,
                    scrollController: FixedExtentScrollController(
                      initialItem: _availableSounds.indexOf(_soundPresets[index]),
                    ),
                    onSelectedItemChanged: (int value) {
                      setState(() {
                        _soundPresets[index] = _availableSounds[value];
                      });
                    },
                    children: _availableSounds.map((sound) {
                      return Center(
                        child: Text(
                          sound.split('/').last.split('.').first,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                  )
                : DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: '알람음',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    value: _soundPresets[index],
                    dropdownColor: const Color(0xFF2E2E2E),
                    style: const TextStyle(color: Colors.white),
                    items: _availableSounds.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value.split('/').last.split('.').first),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _soundPresets[index] = newValue;
                        });
                      }
                    },
                  ),
          ),
        ),
        IconButton(
          icon: Icon(
            _isPlayingList[index] ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            color: Colors.blue,
            size: 28,
          ),
          onPressed: () => _playSound(_soundPresets[index], index),
          tooltip: _isPlayingList[index] ? '중지' : '미리 듣기',
        ),
      ],
    );
  }

  Widget _buildPresetRow(int index) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      color: const Color(0xFF2A2A2A),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Preset ${index + 1}',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTimeSelector(index),
            const SizedBox(height: 12),
            _buildSoundSelector(index),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blue),
            onPressed: () {
              _resetToDefaults();
            },
            tooltip: '초기화',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1E1E1E),
              Colors.blue.withOpacity(0.1),
            ],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Timer Presets',
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 16),
                // ListView.builder 대신 Column과 List.generate 사용
                ...List.generate(
                  4,
                  (index) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildPresetRow(index),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: _savePresets,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 5,
                    ),
                    child: const Text(
                      'Save Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}