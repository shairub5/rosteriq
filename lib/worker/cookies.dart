// Login cookies sent to the bot (/fantrax_cookie). The snapshot lives on a public branch, so a cookie
// is only ever stored AES-GCM encrypted with the COOKIE_KEY repo secret (base64, 32 bytes).
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final _aes = AesGcm.with256bits();

/// base64(nonce + ciphertext + mac).
Future<String> encryptCookie(String cookie, String keyB64) async {
  final box = await _aes.encryptString(cookie, secretKey: SecretKey(base64.decode(keyB64)));
  return base64.encode(box.concatenation());
}

Future<String> decryptCookie(String sealed, String keyB64) => _aes.decryptString(
      SecretBox.fromConcatenation(base64.decode(sealed), nonceLength: _aes.nonceLength, macLength: _aes.macAlgorithm.macLength),
      secretKey: SecretKey(base64.decode(keyB64)),
    );

/// Stored on the league as `fantraxCookie`: {sealed, savedAt, expiredAt?}.
Map<String, dynamic> cookieEntry(String sealed, DateTime now) => {'sealed': sealed, 'savedAt': now.toIso8601String()};

/// "ok" / "expired" / "missing", for /status.
String cookieState(Map<String, dynamic>? entry) => entry == null
    ? 'missing'
    : entry['expiredAt'] != null
        ? 'expired'
        : 'ok';

/// How to copy the cookie; sent for a bare /fantrax_cookie and with the expiry alert.
const fantraxCookieHowTo = 'How to get the Fantrax cookie (on a computer, Chrome):\n'
    '1. Open fantrax.com, logged in.\n'
    '2. F12 (Mac: Cmd+Option+I) → Network tab → reload the page.\n'
    '3. Click the first request in the list → Headers → Request Headers.\n'
    '4. Right-click the "cookie:" line → Copy value.\n'
    '5. Send it here as: /fantrax_cookie <paste>\n'
    'The bot deletes your message after saving it.';
