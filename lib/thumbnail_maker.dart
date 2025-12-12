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
  int _aspectRatioIndex = 0;
  final List<double> _aspectRatios = [1.0, 3/4, 9/16];
  final List<String> _aspectRatioLabels = ['1:1', '3:4', '9:16'];

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
      });
    }
  }

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
            subtitle: Text('Score: ${data['prediction'] ?? '-'}'), 
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _selectAnalysisResult(data),
          ),
        );
      },
    );
  }

  Widget _buildEditor() {
    final data = _selectedAnalysisData!;
    final features = data['feedback_features'] as Map<String, dynamic>? ?? {};

    // 1. Time = total_time
    final String time = features['total_time'] != null 
        ? '${(features['total_time'] as num).toStringAsFixed(1)}s' 
        : '-';
    
    // 2. Distance = fluency_hip_path_length
    final String distance = features['fluency_hip_path_length'] != null 
        ? (features['fluency_hip_path_length'] as num).toStringAsFixed(2) 
        : '-';
    
    // 3. Climbing Pace = fluency_hip_velocity_mean_norm_body
    final String pace = features['fluency_hip_velocity_mean_norm_body'] != null 
        ? (features['fluency_hip_velocity_mean_norm_body'] as num).toStringAsFixed(3) 
        : '-';

    // 4. Smoothness = fluency_hip_jerk_mean
    final String smoothness = features['fluency_hip_jerk_mean'] != null 
        ? (features['fluency_hip_jerk_mean'] as num).toStringAsFixed(3) 
        : '-';

    // 5. Stability = fluency_hip_jerk_rms
    final String stability = features['fluency_hip_jerk_rms'] != null 
        ? (features['fluency_hip_jerk_rms'] as num).toStringAsFixed(3) 
        : '-';

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

          RepaintBoundary(
            key: _imageKey,
            // [수정] 전체 화면의 70% 너비로 다시 변경
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.7,
              child: AspectRatio(
                aspectRatio: _aspectRatios[_aspectRatioIndex],
                child: Container(
                  width: double.infinity,
                  color: Colors.grey[200],
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_imageFile != null)
                        kIsWeb 
                            ? Image.network(_imageFile!.path, fit: BoxFit.cover)
                            : Image.file(File(_imageFile!.path), fit: BoxFit.cover)
                      else
                        const Center(child: Text('Tap "Select Photo"')),

                      if (_imageFile != null)
                        Positioned(
                          top: 20, left: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoText('Time: $time'),
                              _buildInfoText('Distance: $distance'),
                              _buildInfoText('Pace: $pace'),
                              _buildInfoText('Smoothness: $smoothness'),
                              _buildInfoText('Stability: $stability'),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // [수정] Analysis Data 영역을 이미지와 버튼 사이에 위치시키고 가운데 정렬
          const Text('Analysis Data', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                // [수정] 가운데 정렬을 위해 Center로 감쌈
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center, // Row 내부 아이템도 가운데 정렬
                      children: [
                        _buildDataLabel('Time', time),
                        const SizedBox(width: 15),
                        _buildDataLabel('Distance', distance),
                        const SizedBox(width: 15),
                        _buildDataLabel('Pace', pace),
                        const SizedBox(width: 15),
                        _buildDataLabel('Smoothness', smoothness),
                        const SizedBox(width: 15),
                        _buildDataLabel('Stability', stability),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 30),

          // [수정] Select Photo / Save Photo 버튼을 맨 아래로 배치
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo),
                      label: const Text('Select Photo'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saveImage,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                      icon: const Icon(Icons.save_alt),
                      // [수정] 버튼 텍스트 Save -> Save Photo로 변경
                      label: const Text('Save Photo'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildDataLabel(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
      ],
    );
  }

  Widget _buildInfoText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18, 
        fontWeight: FontWeight.bold,
        shadows: [Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1))],
      ),
    );
  }
}
