import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

/// Yahoo OAuth2 login for the app itself - registered as a Public Client
/// (no client secret; that's the point of Public Client apps, a native app
/// can't hold one securely). This only handles connect/store-token/
/// disconnect for now - no API calls are made with the resulting token yet,
/// that's future "Manage Roster" work.
///
/// Client ID comes from --dart-define-from-file=secrets.json (see
/// secrets.json.example) so it never lives in source control.
class YahooAuthService {
  static const _clientId = String.fromEnvironment('YAHOO_CLIENT_ID');
  static const _redirectUri = 'rosteriq://oauth-callback';
  static const _callbackUrlScheme = 'rosteriq';

  static const _authorizeUrl = 'https://api.login.yahoo.com/oauth2/request_auth';
  static const _tokenUrl = 'https://api.login.yahoo.com/oauth2/get_token';

  static const _accessTokenKey = 'yahoo.access_token';
  static const _refreshTokenKey = 'yahoo.refresh_token';

  final _storage = const FlutterSecureStorage();

  bool get isConfigured => _clientId.isNotEmpty;

  Future<bool> isConnected() async {
    final token = await _storage.read(key: _accessTokenKey);
    return token != null && token.isNotEmpty;
  }

  /// Opens the system browser for Yahoo login/consent, then exchanges the
  /// returned authorization code for tokens and stores them securely.
  Future<void> connect() async {
    if (!isConfigured) {
      throw StateError(
        'YAHOO_CLIENT_ID is not set - run with --dart-define-from-file=secrets.json',
      );
    }

    final authorizeUri = Uri.parse(_authorizeUrl).replace(queryParameters: {
      'client_id': _clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'language': 'en-us',
    });

    final resultUrl = await FlutterWebAuth2.authenticate(
      url: authorizeUri.toString(),
      callbackUrlScheme: _callbackUrlScheme,
    );

    final code = Uri.parse(resultUrl).queryParameters['code'];
    if (code == null) {
      throw StateError('Yahoo did not return an authorization code');
    }

    await _exchangeCodeForTokens(code);
  }

  Future<void> _exchangeCodeForTokens(String code) async {
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId,
        'redirect_uri': _redirectUri,
        'code': code,
        'grant_type': 'authorization_code',
      },
    );

    if (response.statusCode != 200) {
      throw StateError('Yahoo token exchange failed: ${response.statusCode} ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final accessToken = body['access_token'] as String?;
    final refreshToken = body['refresh_token'] as String?;
    if (accessToken == null) {
      throw StateError('Yahoo token response had no access_token: ${response.body}');
    }

    await _storage.write(key: _accessTokenKey, value: accessToken);
    if (refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
