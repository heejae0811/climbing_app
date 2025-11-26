import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_html/html.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

class ThumbnailMakerScreen extends StatefulWidget {
  const ThumbnailMakerScreen({super.key});

  @override
  State<ThumbnailMakerScreen> createState() => _ThumbnailMakerScreenState();
}

class _ThumbnailMakerScreenState extends State<ThumbnailMakerScreen> {
  // 0: 분석 리스트 모드, 1: 편집 모드
  int _currentMode = 0;
  List<Map<String, dynamic>> _analysisResults = [];
  Map<String, dynamic>? _selectedAnalysisData;

  XFile? _imageFile;
  final GlobalKey _imageKey = GlobalKey(); 
  bool _isDrawing = false;
  List<Offset> _points = [];
  int _aspectRatioIndex = 0;
  final List<double> _aspectRatios = [1.0, 9/16, 3/4];
  final List<String> _aspectRatioLabels = ['1:1', '9:16', '3:4'];

  @override
  void initState() {
    super.initState();
    _loadAnalysisResults();
    analysisUpdateNotifier.addListener(_loadAnalysisResults);
  }

  @override
  void dispose() {
    analysisUpdateNotifier.removeListener(_loadAnalysisResults);
    super.dispose();
  }

  Future<void> _loadAnalysisResults() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final List<String>? results = prefs.getStringList('analysis_results');
    if (results != null) {
      setState(() {
        _analysisResults = results.map((e) => json.decode(e) as Map<String, dynamic>).toList();
      });
    }
  }

  void _selectAnalysisResult(Map<String, dynamic> data) {
    setState(() {
      _selectedAnalysisData = data;
      _currentMode = 1; 
      _imageFile = null; 
      _points.clear();
    });
  }

  void _goBackToList() {
    setState(() {
      _currentMode = 0;
      _selectedAnalysisData = null;
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
        _points.clear();
      });
    }
  }

  void _clearDrawing() => setState(() => _points.clear());

  Future<void> _saveImage() async {
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an image first.')));
      return;
    }

    if (kIsWeb) {
      try {
        RenderRepaintBoundary boundary = _imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
        ui.Image image = await boundary.toImage(pixelRatio: 3.0);
        ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final Uint8List pngBytes = byteData!.buffer.asUint8List();

        final blob = html.Blob([pngBytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)..setAttribute("download", "climbing_thumbnail.png")..click();
        html.Url.revokeObjectUrl(url);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image downloaded!')));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving on web: $e')));
      }
      return;
    }

    if (Platform.isAndroid) {
      if (await Permission.storage.request().isGranted || await Permission.photos.request().isGranted) {}
    } else if (Platform.isIOS) {
      if (await Permission.photos.request().isGranted) {}
    }

    try {
      RenderRepaintBoundary boundary = _imageKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final result = await ImageGallerySaver.saveImage(pngBytes, quality: 100, name: "climbing_thumbnail_${DateTime.now().millisecondsSinceEpoch}");
      
      bool isSuccess = false;
      if (result is Map) {
        isSuccess = result['isSuccess'] ?? false;
      } else if (result is bool) {
        isSuccess = result;
      }

      if (isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to Gallery!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save image.')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving image: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thumbnail Maker'),
        leading: _currentMode == 1 
          ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: _goBackToList) 
          : null,
        actions: [
          if (_currentMode == 0)
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAnalysisResults, tooltip: 'Refresh List'),
        ],
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: analysisUpdateNotifier,
        builder: (context, value, child) {
          return _currentMode == 0 ? _buildList() : _buildEditor();
        },
      ),
    );
  }

  Widget _buildList() {
    if (_analysisResults.isEmpty) {
      return const Center(
        child: Text('저장된 분석 결과가 없습니다.\n영상 분석 탭에서 영상을 분석해보세요!', textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      itemCount: _analysisResults.length,
      padding: const EdgeInsets.all(16.0),
      itemBuilder: (context, index) {
        final data = _analysisResults[index];
        String dateStr = 'Unknown Date';
        if (data['date'] != null) {
          try {
            final date = DateTime.parse(data['date']);
            dateStr = '${date.month}/${date.day} ${date.hour}:${date.minute}';
          } catch (e) {
            dateStr = data['date'];
          }
        }

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.analytics)),
            title: Text('Analysis - $dateStr'),
            subtitle: Text('Time: ${data['ascent_time']}s'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _selectAnalysisResult(data),
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    double currentRatio = _aspectRatios[_aspectRatioIndex];
    
    final data = _selectedAnalysisData!;
    // [수정] 요청하신 변수명(Distance, Speed, Time, Smoothness)으로 매핑
    // 데이터가 없으면 '-' (빈값/기본값) 처리
    final String distance = data['total_distance']?.toString() ?? '-';
    final String speed = data['avg_speed']?.toString() ?? '-';
    final String time = data['ascent_time']?.toString() ?? '-';
    final String smoothness = data['jerk_rms']?.toString() ?? '-';

    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ToggleButtons(
              isSelected: List.generate(3, (index) => index == _aspectRatioIndex),
              onPressed: (int index) => setState(() => _aspectRatioIndex = index),
              children: _aspectRatioLabels.map((label) => Padding(padding: const EdgeInsets.symmetric(horizontal: 16.0), child: Text(label))).toList(),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: RepaintBoundary(
              key: _imageKey,
              child: AspectRatio(
                aspectRatio: currentRatio,
                child: Container(
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      if (_isDrawing) setState(() => _points.add(details.localPosition));
                    },
                    onPanEnd: (_) {},
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_imageFile != null)
                          kIsWeb 
                              ? Image.network(_imageFile!.path, fit: BoxFit.cover)
                              : Image.file(File(_imageFile!.path), fit: BoxFit.cover)
                        else
                          const Center(child: Text('Tap "Select Photo"')),

                        CustomPaint(painter: TrajectoryPainter(points: _points), size: Size.infinite),

                        // [수정] 오버레이 정보 4가지 표시
                        if (_imageFile != null)
                          Positioned(
                            top: 20, left: 20,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText('Distance: $distance m'),
                                _buildInfoText('Speed: $speed km/h'),
                                _buildInfoText('Time: ${time}s'),
                                _buildInfoText('Smoothness: $smoothness'),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo),
                      label: const Text('Select Photo'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: _isDrawing ? Colors.redAccent : null),
                      onPressed: _imageFile == null ? null : () => setState(() => _isDrawing = !_isDrawing),
                      icon: const Icon(Icons.edit),
                      label: Text(_isDrawing ? 'Stop Drawing' : 'Draw Path'),
                    ),
                    IconButton(onPressed: _clearDrawing, icon: const Icon(Icons.refresh), tooltip: 'Clear Path'),
                  ],
                ),
                const SizedBox(height: 20),
                
                const Text('Selected Analysis Data', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                // [수정] 데이터 정보 카드도 4가지 변수로 업데이트
                Card(
                  color: Colors.grey[100],
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDataLabel('Distance', distance),
                        _buildDataLabel('Speed', speed),
                        _buildDataLabel('Time', '${time}s'),
                        _buildDataLabel('Smoothness', smoothness),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saveImage,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                    icon: const Icon(Icons.save_alt),
                    label: const Text('Save to Gallery', style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataLabel(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), // 폰트 사이즈 살짝 조정
      ],
    );
  }

  Widget _buildInfoText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1))],
      ),
    );
  }
}

class TrajectoryPainter extends CustomPainter {
  final List<Offset> points;
  TrajectoryPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent..strokeCap = StrokeCap.round..strokeWidth = 4.0;
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
