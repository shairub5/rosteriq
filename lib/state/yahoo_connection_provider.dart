import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/yahoo_auth_service.dart';

final yahooAuthServiceProvider = Provider((ref) => YahooAuthService());

enum YahooConnectionStatus { unknown, notConnected, connected, connecting, error }

class YahooConnectionState {
  final YahooConnectionStatus status;
  final String? errorMessage;

  const YahooConnectionState(this.status, {this.errorMessage});
}

class YahooConnectionNotifier extends StateNotifier<YahooConnectionState> {
  final YahooAuthService _service;

  YahooConnectionNotifier(this._service) : super(const YahooConnectionState(YahooConnectionStatus.unknown)) {
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    final connected = await _service.isConnected();
    state = YahooConnectionState(
      connected ? YahooConnectionStatus.connected : YahooConnectionStatus.notConnected,
    );
  }

  Future<void> connect() async {
    state = const YahooConnectionState(YahooConnectionStatus.connecting);
    try {
      await _service.connect();
      state = const YahooConnectionState(YahooConnectionStatus.connected);
    } catch (e) {
      state = YahooConnectionState(YahooConnectionStatus.error, errorMessage: e.toString());
    }
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    state = const YahooConnectionState(YahooConnectionStatus.notConnected);
  }
}

final yahooConnectionProvider = StateNotifierProvider<YahooConnectionNotifier, YahooConnectionState>((ref) {
  return YahooConnectionNotifier(ref.watch(yahooAuthServiceProvider));
});
