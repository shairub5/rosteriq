import 'dart:io';

import 'package:http/http.dart' as http;

/// Sends each text as its own message. Without a token/chat id the texts are only printed.
Future<void> sendTelegram(List<String> texts, {required String? token, required String? chatId}) async {
  if (token == null || chatId == null) {
    stderr.writeln('TELEGRAM_TOKEN / TELEGRAM_CHAT_ID not set - alerts printed only');
    return;
  }
  for (final text in texts) {
    final res = await http.post(
      Uri.parse('https://api.telegram.org/bot$token/sendMessage'),
      body: {'chat_id': chatId, 'text': text},
    );
    if (res.statusCode != 200) stderr.writeln('Telegram ${res.statusCode}: ${res.body}');
  }
}
