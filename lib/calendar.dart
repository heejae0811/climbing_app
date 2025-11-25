import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

// 운동 기록 데이터 모델
class WorkoutLog {
  final int condition; // 1(힘듦), 2(보통), 3(좋음)
  final int duration; // 분 단위
  final String memo;

  WorkoutLog({required this.condition, required this.duration, required this.memo});

  factory WorkoutLog.fromJson(Map<String, dynamic> json) {
    return WorkoutLog(
      condition: json['condition'] as int,
      duration: json['duration'] as int,
      memo: json['memo'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'condition': condition,
    'duration': duration,
    'memo': memo,
  };
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, WorkoutLog> _events = {};

  // [수정] 3단계 컨디션 아이콘 및 라벨
  final List<IconData> _conditionIcons = [Icons.sentiment_very_dissatisfied, Icons.sentiment_neutral, Icons.sentiment_very_satisfied];
  final List<String> _conditionLabels = ['힘듦', '보통', '좋음'];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsString = prefs.getString('workout_events_v3'); // 키 이름 변경
    if (eventsString != null) {
      final decodedEvents = json.decode(eventsString) as Map<String, dynamic>;
      setState(() {
        _events = decodedEvents.map((key, value) => MapEntry(key, WorkoutLog.fromJson(value)));
      });
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedEvents = _events.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString('workout_events_v3', json.encode(encodedEvents));
  }

  List<WorkoutLog> _getEventsForDay(DateTime day) {
    final dayString = DateUtils.dateOnly(day).toIso8601String();
    return _events[dayString] != null ? [_events[dayString]!] : [];
  }

  void _onDaySelected(DateTime selectedDay, DateTime focusedDay) {
    setState(() {
      _selectedDay = selectedDay;
      _focusedDay = focusedDay;
    });
    _showAddLogDialog(selectedDay);
  }

  Future<void> _showAddLogDialog(DateTime day) async {
    final dayString = DateUtils.dateOnly(day).toIso8601String();
    final existingLog = _events[dayString];

    int currentCondition = existingLog?.condition ?? 2; // 기본값 '보통'
    final durationController = TextEditingController(text: existingLog?.duration.toString() ?? '60');
    final memoController = TextEditingController(text: existingLog?.memo ?? '');

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('${day.month}/${day.day} 운동 기록'),
              // [수정] 스크롤이 필요 없도록 content의 크기를 늘림
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('오늘의 컨디션', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(3, (index) {
                      return Column(
                        children: [
                          IconButton(
                            icon: Icon(_conditionIcons[index], size: 40),
                            color: index + 1 == currentCondition ? _getConditionColor(index + 1) : Colors.grey[400],
                            onPressed: () => setDialogState(() => currentCondition = index + 1),
                          ),
                          Text(_conditionLabels[index], style: TextStyle(fontSize: 12, color: index + 1 == currentCondition ? _getConditionColor(index + 1) : Colors.grey[400])),
                        ],
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '운동 시간 (분)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: memoController,
                    decoration: const InputDecoration(labelText: '한 줄 메모', border: OutlineInputBorder()),
                  ),
                ],
              ),
              actions: [
                TextButton(child: const Text('취소'), onPressed: () => Navigator.of(context).pop()),
                if (existingLog != null)
                  TextButton(
                    child: const Text('삭제', style: TextStyle(color: Colors.red)),
                    onPressed: () {
                      setState(() => _events.remove(dayString));
                      _saveEvents();
                      Navigator.of(context).pop();
                    },
                  ),
                ElevatedButton(
                  child: const Text('저장'),
                  onPressed: () {
                    final newLog = WorkoutLog(
                      condition: currentCondition,
                      duration: int.tryParse(durationController.text) ?? 60,
                      memo: memoController.text,
                    );
                    setState(() => _events[dayString] = newLog);
                    _saveEvents();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Workout Calendar')),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: _onDaySelected,
            eventLoader: _getEventsForDay,
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(color: Colors.deepPurpleAccent, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, events) {
                if (events.isNotEmpty) {
                  final log = events.first as WorkoutLog;
                  return Positioned(
                    right: 1, bottom: 1,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: _getConditionColor(log.condition)),
                    ),
                  );
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 8.0),
          const Divider(),
          Expanded(
            child: _buildLogDetails(),
          ),
        ],
      ),
    );
  }

  // [수정] 3단계 컨디션에 따른 색상 반환
  Color _getConditionColor(int condition) {
    switch (condition) {
      case 1: return Colors.red; // 힘듦
      case 2: return Colors.green; // 보통
      case 3: return Colors.blue; // 좋음
      default: return Colors.grey;
    }
  }

  Widget _buildLogDetails() {
    final events = _getEventsForDay(_selectedDay!);
    if (events.isEmpty) {
      return const Center(child: Text('운동 기록이 없습니다.\n날짜를 눌러 기록을 추가하세요.', textAlign: TextAlign.center,));
    }
    final log = events.first;
    return Card(
      margin: const EdgeInsets.all(12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_selectedDay!.month}/${_selectedDay!.day} 운동 기록', style: Theme.of(context).textTheme.titleLarge),
            const Divider(height: 20),
            Row(
              children: [
                const Text('컨디션: ', style: TextStyle(fontWeight: FontWeight.bold)),
                Icon(_conditionIcons[log.condition - 1], color: _getConditionColor(log.condition)),
                const SizedBox(width: 8),
                Text(_conditionLabels[log.condition - 1], style: TextStyle(color: _getConditionColor(log.condition), fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text('운동 시간: ${log.duration}분', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (log.memo.isNotEmpty)
              Text('메모: ${log.memo}'),
          ],
        ),
      ),
    );
  }
}
