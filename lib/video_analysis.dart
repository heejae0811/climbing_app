import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_key.dart';
import 'main.dart'; // 전역 Notifier 접근

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
      // [수정] 모델 초기화 시 바로 채팅 세션 시작
      _chat = _model!.startChat(); 
    }
    
    // [수정] 초기 메시지 바로 추가
    _messages.add(ChatMessage(
      text: '클라이밍 AI 코치입니다. 분석할 영상을 업로드 하거나 궁금한 게 있으면 물어보세요.', 
      isUser: false
    ));
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
      // 리셋 시에도 초기 메시지 다시 추가
      _messages.add(ChatMessage(
        text: '클라이밍 AI 코치입니다. 분석할 영상을 업로드 하거나 궁금한 게 있으면 물어보세요.', 
        isUser: false
      ));
      _chat = _model?.startChat(); // 채팅 세션도 초기화
      _isAnalyzing = false;
      _statusMessage = '';
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
    Map<String, dynamic>? analysisData;
    List<dynamic>? serverFeedback;
    String? prediction;
    Map<String, dynamic>? rawPrediction;

    try {
      final uri = Uri.parse('http://127.0.0.1:5001/predict');

      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromBytes('video', await videoFile.readAsBytes(), filename: videoFile.name));

      setState(() => _statusMessage = 'Analyzing video...');
      final response = await http.Response.fromStream(await request.send());

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          throw FormatException('Unexpected response format: $decoded');
        }
        final jsonResponse = decoded;

        dynamic features;
        if (jsonResponse.containsKey('feedback_features')) {
          features = jsonResponse['feedback_features'];
        } else if (jsonResponse.containsKey('feature_values')) {
          features = jsonResponse['feature_values'];
        }

        if (features != null) {
          if (features is Map<String, dynamic>) {
            analysisData = features;
          } else if (features is Map) {
            analysisData = Map<String, dynamic>.from(features);
          }
        }

        dynamic fb;
        if (jsonResponse.containsKey('feedback_messages')) {
          fb = jsonResponse['feedback_messages'];
        } else if (jsonResponse.containsKey('feedback')) {
          fb = jsonResponse['feedback'];
        }

        if (fb is List) {
          serverFeedback = fb;
        }

        if (jsonResponse.containsKey('prediction')) {
          final pred = jsonResponse['prediction'];
          if (pred is Map) {
            rawPrediction = Map<String, dynamic>.from(pred);
            prediction = rawPrediction['label']?.toString();
          } else {
            prediction = pred?.toString();
          }
        }

        final dataToSave = <String, dynamic>{
          'date': DateTime.now().toIso8601String(),
        };
        if (analysisData != null) dataToSave['feedback_features'] = analysisData;
        if (serverFeedback != null) dataToSave['feedback_messages'] = serverFeedback;
        
        if (rawPrediction != null) {
          dataToSave['prediction'] = rawPrediction;
        } else if (prediction != null) {
          dataToSave['prediction'] = prediction;
        }

        if (analysisData != null || serverFeedback != null) {
          await _saveAnalysisResult(dataToSave);
        } else {
           print('Warning: No analysis data found in response. Keys: ${jsonResponse.keys}');
        }

      } else {
        _handleError('Analysis failed: ${response.reasonPhrase}\n${response.body}');
        return;
      }
    } catch (e) {
      _handleError('An error occurred during analysis: $e');
      return;
    }

    if (analysisData != null || serverFeedback != null) {
      setState(() => _statusMessage = 'AI Coach is generating feedback...');
      await _getInitialFeedback(analysisData ?? {}, serverFeedback, prediction);
    } else {
      _handleError('No analysis data received. (Check JSON keys)');
    }
    setState(() => _isAnalyzing = false);
  }

  Future<void> _saveAnalysisResult(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      List<String> history = prefs.getStringList('analysis_results') ?? [];
      
      if (!data.containsKey('date')) {
        data['date'] = DateTime.now().toIso8601String();
      }
      history.insert(0, json.encode(data));
      await prefs.setStringList('analysis_results', history);
      analysisUpdateNotifier.value = !analysisUpdateNotifier.value;
    } catch (e) {
      print('Error saving analysis result: $e');
    }
  }

  Future<void> _getInitialFeedback(Map<String, dynamic> analysisData, List<dynamic>? serverFeedback, String? prediction) async {
    if (_model == null) {
      _handleError('Error: AI Model is not initialized.');
      return;
    }

    final prompt = """You are a professional climbing coach. I have uploaded a new climbing video.
The server analysis provided the following results:

[Prediction]
${prediction ?? 'Unknown'}

[Analysis Data]
${analysisData.entries.map((e) => '- ${e.key}: ${e.value}').join('\n')}

[Server Feedback]
${serverFeedback?.join('\n') ?? 'No specific feedback provided.'}

Based on this information, please:
1. Summarize the server's feedback in a friendly and encouraging tone.
2. Explain what the analysis values mean for my climbing (e.g., jerk, velocity).
3. Provide specific advice to improve my climbing technique.
Please provide your response in Korean.""";

    try {
      if (_chat == null) {
        _chat = _model!.startChat();
      }

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
            // [수정] _messages가 비어있을 때 표시하던 초기 화면(버튼 2개) 제거하고
            // 항상 리스트뷰를 표시하도록 변경 (초기 메시지가 항상 있으므로)
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
              itemCount: _messages.length + (_isAnalyzing ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
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
          ),
          _buildTextComposer(), // 항상 입력창 표시
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
