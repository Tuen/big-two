import "package:big_two/online/snapshot.dart";
import "package:supabase_flutter/supabase_flutter.dart";

class GameException implements Exception {
  final String message;
  GameException(this.message);
  @override
  String toString() => message;
}

class GameApi {
  final SupabaseClient client;
  GameApi(this.client);

  Future<void> ensureSession() async {
    if (client.auth.currentSession != null) return;
    final result = await client.auth.signInAnonymously();
    if (result.session == null) {
      throw GameException("Sign-in failed. In the Supabase dashboard, turn on Anonymous sign-ins.");
    }
  }

  /// Pressing Exit. Closing the app does not call this, so the seat stays held.
  Future<void> leave(String tableId) async {
    try {
      final response = await client.functions.invoke("table", body: {"action": "exit", "tableId": tableId});
      final data = _asMap(response.data);
      if (data["error"] is String) throw GameException(data["error"] as String);
      if (data["left"] == true) return;
      throw GameException("The table could not be updated");
    } on GameException {
      rethrow;
    } on FunctionException catch (error) {
      throw GameException(_functionMessage(error));
    }
  }

  Future<TableSnapshot> call(String function, Map<String, dynamic> body) async {
    try {
      final response = await client.functions.invoke(function, body: body);
      final data = _asMap(response.data);
      if (data["error"] is String) throw GameException(data["error"] as String);
      return TableSnapshot.fromJson(_asMap(data["view"]));
    } on GameException {
      rethrow;
    } on FunctionException catch (error) {
      throw GameException(_functionMessage(error));
    }
  }

  String _functionMessage(FunctionException error) {
    final details = error.details;
    if (details is Map && details["error"] is String) return details["error"] as String;
    if (details is String && details.isNotEmpty) return details;
    return "The table could not be updated";
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
  throw GameException("Unexpected reply from the server");
}
