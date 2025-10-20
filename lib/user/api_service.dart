import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = 'http://192.168.1.121:8000'; // 👈 your local IP

  static Future<String> getBotResponse(String userMessage) async {
    final url = Uri.parse('$baseUrl/chat');
    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'message': userMessage}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['response'] ?? "No response from bot.";
      } else {
        return "Failed to get response. (${response.statusCode})";
      }
    } catch (e) {
      return "Failed to connect to DHVBot. Make sure the server is running.";
    }
  }
}
