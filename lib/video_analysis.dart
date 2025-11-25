import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
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
  String _statusMessage = 'Select a video to start analysis.';

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
    // 영상 선택 시 항상 상태를 초기화하여, 새 분석을 시작하도록 함
    _resetState();

    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);
    if (video != null) {
      setState(() {
        _video = video;
        _isAnalyzing = true;
      });
      _uploadAndGetFeedback(video);
    }
  }

  Future<void> _uploadAndGetFeedback(XFile videoFile) async {
    setState(() => _statusMessage = 'Uploading and analyzing video...');
    Map<String, dynamic>? analysisData;

    try {
      final uri = Uri.parse('http://127.0.0.1:5001/predict');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromBytes('video', await videoFile.readAsBytes(), filename: videoFile.name));
      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        analysisData = (json.decode(response.body) as Map<String, dynamic>)['gpt_prompt_data'];
      } else {
        _handleError('Analysis failed: ${response.reasonPhrase}\n${response.body}');
        return;
      }
    } catch (e) {
      _handleError('An error occurred during analysis: $e');
      return;
    }

    if (analysisData != null) {
      setState(() => _statusMessage = 'AI Coach is generating initial feedback...');
      await _getInitialFeedback(analysisData);
    }
    setState(() => _isAnalyzing = false);
  }

  Future<void> _getInitialFeedback(Map<String, dynamic> analysisData) async {
    if (_model == null) {
      _handleError('Error: AI Model is not initialized. Please check your API key in secrets.dart.');
      return;
    }
    final prompt = """You are a professional climbing coach. After analyzing the user's climbing video, you are providing the initial feedback. Keep the feedback concise and encouraging, then ask if they have any questions.

[Analysis Data]
- Movement Efficiency (Path Inefficiency): ${analysisData['path_inefficiency']}
- Hesitation (Immobility Ratio): ${(analysisData['immobility_ratio'] * 100).toStringAsFixed(1)}%
- Movement Smoothness (Jerk RMS): ${analysisData['jerk_rms']}
- Total Ascent Time: ${analysisData['ascent_time']} seconds

Based on this data, provide your feedback in Korean.""";

    try {
      final response = await _model!.generateContent([Content.text(prompt)]);
      final initialFeedback = response.text ?? 'No feedback received.';

      if (response.candidates.isNotEmpty) {
        final modelResponseContent = response.candidates.first.content;
        setState(() {
          _chat = _model!.startChat(history: [Content.text(prompt), modelResponseContent]);
          _messages.add(ChatMessage(text: initialFeedback, isUser: false));
        });
      } else {
        _handleError('AI coach did not provide a valid response.');
      }
    } catch (e) {
      _handleError('Failed to get feedback from AI coach.\nError: ${e.toString()}');
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
      ),
      // [수정] 오른쪽 하단에 플로팅 액션 버튼 추가
      floatingActionButton: (!_isAnalyzing && _messages.isNotEmpty)
          ? FloatingActionButton.extended(
        onPressed: _resetState, // 버튼을 누르면 모든 상태 초기화
        label: const Text('New Analysis'),
        icon: const Icon(Icons.replay),
      )
          : null,
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            if (!_isAnalyzing && _messages.isEmpty)
              Expanded(
                child: Center(
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
                ),
              ),
            if (_isAnalyzing)
              const Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text('Analyzing...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            if (_messages.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                ),
              ),
            if (!_isAnalyzing && _messages.isNotEmpty) _buildTextComposer(),
          ],
        ),
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: TextField(
                controller: _chatController,
                onSubmitted: _sendChatMessage,
                decoration: const InputDecoration.collapsed(hintText: 'Ask a follow-up question...'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: () => _sendChatMessage(_chatController.text),
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
