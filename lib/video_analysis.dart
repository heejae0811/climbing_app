import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_key.dart';

// 채팅 메시지를 위한 데이터 클래스
class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class VideoAnalysisScreen extends StatefulWidget {
  const VideoAnalysisScreen({super.key});

  @override
  State<VideoAnalysisScreen> createState() => _VideoAnalysisScreenState();
}

class _VideoAnalysisScreenState extends State<VideoAnalysisScreen> {
  XFile? _video;
  bool _isAnalyzing = false;
  // _statusMessage는 이제 UI에서 직접적으로 쓰기보다 로딩 상태 표시에 활용
  String _statusMessage = '';

  final TextEditingController _chatController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  GenerativeModel? _model;
  ChatSession? _chat;

  @override
  void initState() {
    super.initState();
    if (googleApiKey.isNotEmpty && !googleApiKey.startsWith('YOUR_')) {
      _model = GenerativeModel(model: 'gemini-flash-latest', apiKey: googleApiKey);
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _resetState() {
    setState(() {
      _video = null;
      _messages.clear();
      _chat = null;
      _isAnalyzing = false;
      _statusMessage = 'Select a video to start analysis.';
    });
  }

  Future<void> _pickVideo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      setState(() {
        _video = video;
        _isAnalyzing = true;
        _statusMessage = 'Uploading video...';
        _messages.add(ChatMessage(text: '[Video Uploaded: ${video.name}]', isUser: true));
      });
      _scrollToBottom();
      _uploadAndGetFeedback(video);
    }
  }

  Future<void> _uploadAndGetFeedback(XFile videoFile) async {
    // 분석 시작
    Map<String, dynamic>? analysisData;

    try {
      final uri = Uri.parse('http://127.0.0.1:5001/predict');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromBytes('video', await videoFile.readAsBytes(), filename: videoFile.name));
      
      setState(() => _statusMessage = 'Analyzing video...');
      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        analysisData = (json.decode(response.body) as Map<String, dynamic>)['gpt_prompt_data'];
        
        // [추가] 분석 결과를 로컬(SharedPreferences)에 저장
        if (analysisData != null) {
          await _saveAnalysisResult(analysisData);
        }

      } else {
        _handleError('Analysis failed: ${response.reasonPhrase}\n${response.body}');
        return;
      }
    } catch (e) {
      _handleError('An error occurred during analysis: $e');
      return;
    }

    if (analysisData != null) {
      setState(() => _statusMessage = 'AI Coach is generating feedback...');
      await _getInitialFeedback(analysisData);
    }
    setState(() => _isAnalyzing = false);
  }

  // [추가] 분석 결과 저장 메서드
  Future<void> _saveAnalysisResult(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList('analysis_results') ?? [];
      
      // 데이터에 날짜 추가 (리스트 식별용)
      data['date'] = DateTime.now().toIso8601String();
      
      // 최신 데이터가 위로 오도록 추가
      history.insert(0, json.encode(data));
      await prefs.setStringList('analysis_results', history);
    } catch (e) {
      print('Error saving analysis result: $e');
    }
  }

  Future<void> _getInitialFeedback(Map<String, dynamic> analysisData) async {
    if (_model == null) {
      _handleError('Error: AI Model is not initialized. Please check your API key in secrets.dart.');
      return;
    }
    
    // 프롬프트 구성
    final prompt = """You are a professional climbing coach. I have uploaded a new climbing video.
Analyze the following data extracted from the video:

[Analysis Data]
- Movement Efficiency (Path Inefficiency): ${analysisData['path_inefficiency']}
- Hesitation (Immobility Ratio): ${(analysisData['immobility_ratio'] * 100).toStringAsFixed(1)}%
- Movement Smoothness (Jerk RMS): ${analysisData['jerk_rms']}
- Total Ascent Time: ${analysisData['ascent_time']} seconds

Based on this new data, provide your feedback in Korean. Compare it with previous attempts if possible.""";

    try {
      // 채팅 세션이 없으면 시작
      if (_chat == null) {
        _chat = _model!.startChat();
      }

      // 메시지 전송 (이전 대화 문맥 유지)
      final response = await _chat!.sendMessage(Content.text(prompt));
      final initialFeedback = response.text ?? 'No feedback received.';

      setState(() {
        _messages.add(ChatMessage(text: initialFeedback, isUser: false));
      });
    } catch (e) {
      _handleError('Failed to get feedback from AI coach.\nError: ${e.toString()}');
    } finally {
      _scrollToBottom();
    }
  }

  Future<void> _sendChatMessage(String text) async {
    if (text.isEmpty || _chat == null) return;
    _chatController.clear();

    setState(() => _messages.add(ChatMessage(text: text, isUser: true)));
    _scrollToBottom();

    try {
      final response = await _chat!.sendMessage(Content.text(text));
      final responseText = response.text;
      setState(() => _messages.add(ChatMessage(text: responseText ?? '...', isUser: false)));
    } catch (e) {
      _handleError('Error sending message: ${e.toString()}');
    } finally {
      _scrollToBottom();
    }
  }

  void _handleError(String errorMessage) {
    setState(() {
      _messages.add(ChatMessage(text: errorMessage, isUser: false));
      _isAnalyzing = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Video Analysis & Feedback'),
        actions: [
          // 대화 초기화 버튼 추가
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetState,
            tooltip: 'New Chat',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: _messages.isEmpty && !_isAnalyzing
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.video_camera_front_outlined, size: 60, color: Colors.grey),
                          const SizedBox(height: 20),
                          const Text('Analyze your climbing video to start a conversation with the AI Coach.', textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.video_library),
                            onPressed: _pickVideo,
                            label: const Text('Select Video'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                        itemCount: _messages.length + (_isAnalyzing ? 1 : 0), // 로딩 인디케이터를 위한 아이템 추가
                        itemBuilder: (context, index) {
                          if (index == _messages.length) {
                            // 마지막 아이템으로 로딩 표시
                            return Container(
                              padding: const EdgeInsets.all(16.0),
                              alignment: Alignment.center,
                              child: Column(
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 8),
                                  Text(_statusMessage, style: const TextStyle(color: Colors.grey)),
                                ],
                              ),
                            );
                          }
                          return _buildMessageBubble(_messages[index]);
                        },
                      ),
                    ],
                  ),
          ),
          // 입력창은 분석 중이 아닐 때 혹은 메시지가 있을 때 표시
          if (_messages.isNotEmpty || _isAnalyzing) _buildTextComposer(),
        ],
      ),
    );
  }

  Widget _buildTextComposer() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          // 영상 추가 버튼
          IconButton(
            icon: const Icon(Icons.video_library),
            onPressed: _isAnalyzing ? null : _pickVideo,
            tooltip: 'Add Video',
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: TextField(
                controller: _chatController,
                onSubmitted: _isAnalyzing ? null : _sendChatMessage,
                enabled: !_isAnalyzing,
                decoration: const InputDecoration.collapsed(hintText: 'Ask a question...'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isAnalyzing ? null : () => _sendChatMessage(_chatController.text),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final align = message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = message.isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.secondary;
    final textColor = message.isUser ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSecondary;

    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
          decoration: BoxDecoration(
            color: color.withOpacity(0.9),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: message.isUser ? const Radius.circular(20) : Radius.zero,
              bottomRight: message.isUser ? Radius.zero : const Radius.circular(20),
            ),
          ),
          child: Text(message.text, style: TextStyle(color: textColor, fontSize: 16)),
        ),
      ],
    );
  }
}
