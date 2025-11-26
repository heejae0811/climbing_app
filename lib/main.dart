import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'chatbot.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
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

  // [수정] 탭 순서 변경: 영상 분석 - 썸네일 만들기 - 달력 - AI 코치
  static const List<Widget> _widgetOptions = <Widget>[
    VideoAnalysisScreen(), // 0번 탭: 영상 분석
    ThumbnailMakerScreen(), // 1번 탭: 썸네일 (순서 변경)
    CalendarScreen(),      // 2번 탭: 캘린더
    ChatScreen(),          // 3번 탭: AI 코치 (순서 변경)
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
            icon: Icon(Icons.image), // 썸네일 아이콘
            label: '썸네일',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month),
            label: '캘린더',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble), // AI 코치 아이콘
            label: 'AI 코치',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }
}
