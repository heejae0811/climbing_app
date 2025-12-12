import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'calendar.dart';
import 'video_analysis.dart';
import 'thumbnail_maker.dart';

// [추가] 전역 Notifier
final ValueNotifier<bool> analysisUpdateNotifier = ValueNotifier(false);

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Climbing AI App',
      debugShowCheckedModeBanner: false, // 디버그 띠 제거
      theme: ThemeData(
        // [수정] 사용자가 처음 요청했던 Indigo 색상으로 복원
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        textTheme: GoogleFonts.notoSansKrTextTheme(
          Theme.of(context).textTheme,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  // 탭 순서: 영상 분석 - 썸네일 만들기 - 달력
  final List<Widget> _widgetOptions = <Widget>[
    const VideoAnalysisScreen(), // 0번 탭
    const ThumbnailMakerScreen(), // 1번 탭
    const CalendarScreen(),      // 2번 탭
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _widgetOptions,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.video_camera_front),
            label: '영상 분석',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.image),
            label: '썸네일',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: '캘린더',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.indigo, // [수정] 탭 선택 색상도 Indigo로 복원
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}
