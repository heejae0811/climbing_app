import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'api_key.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();

  GenerativeModel? _model;
  ChatSession? _chat;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      if (googleApiKey.startsWith('YOUR_') || googleApiKey.isEmpty) {
        throw Exception('API key is not set in secrets.dart. Please add your key.');
      }
      _model = GenerativeModel(model: 'gemini-flash-latest', apiKey: googleApiKey);
      _chat = _model!.startChat();

      setState(() {
        _messages.add(ChatMessage(
          text: '안녕하세요! 저는 당신의 클라이밍 AI 코치입니다. 무엇이든 물어보세요.',
          isUser: false,
        ));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Failed to initialize AI Coach.\nError: ${e.toString()}',
          isUser: false,
        ));
      });
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty || _chat == null) return;
    _chatController.clear();

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
    });
    _scrollToBottom();

    try {
      final response = await _chat!.sendMessage(Content.text(text));
      final responseText = response.text;

      if (responseText != null) {
        setState(() {
          _messages.add(ChatMessage(text: responseText, isUser: false));
        });
      } else {
        _messages.add(ChatMessage(text: 'No response from AI.', isUser: false));
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(text: 'Error: ${e.toString()}', isUser: false));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Coach Chat')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: CircularProgressIndicator(),
            ),
          _buildTextComposer(),
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: TextField(
                controller: _chatController,
                onSubmitted: _isLoading ? null : _sendMessage,
                decoration: const InputDecoration.collapsed(hintText: 'Send a message...'),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _isLoading ? null : () => _sendMessage(_chatController.text),
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
