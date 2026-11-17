import "package:big_two/online/snapshot.dart";
import "package:big_two/rules/cards.dart";
import "package:big_two/rules/game.dart";
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

  /// Other players' leftover cards, from the deal and the play log already stored.
  /// Returns null when this phone cannot read them (for example a watcher).
  Future<List<List<PlayingCard>>?> finishedHands({
    required String tableId,
    required int round,
    required int hand,
    required Settings settings,
  }) async {
    try {
      final row = await client
          .from("hands")
          .select("id, first_hand, previous_winner, running_at_start, deck_reveal")
          .eq("table_id", tableId)
          .eq("round_number", round)
          .eq("hand_number", hand)
          .maybeSingle();
      if (row == null) return null;
      final deck = row["deck_reveal"]?.toString() ?? "";
      if (deck.isEmpty) return null;
      final rawEvents = await client.from("events").select("seq, seat_index, kind, payload").eq("hand_id", row["id"]).order("seq");
      final events = [
        for (final item in rawEvents as List)
          ReplayEvent(
            kind: _asMap(item)["kind"]?.toString() ?? "pass",
            seat: _asInt(_asMap(item)["seat_index"]),
            cards: _eventCards(_asMap(item)["payload"]),
          ),
      ];
      final step = replay(
        parseCards(deck.split(",")),
        _ints(row["running_at_start"]),
        row["first_hand"] == true,
        row["previous_winner"] == null ? null : _asInt(row["previous_winner"]),
        events,
        settings,
      );
      if (step is! StepOk || step.state.status != "complete") return null;
      return step.state.hands;
    } catch (_) {
      return null;
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

int _asInt(dynamic value) => value is int ? value : int.parse("$value");

List<int> _ints(dynamic value) {
  if (value is List) return [for (final item in value) _asInt(item)];
  return const [0, 0, 0, 0];
}

List<String> _eventCards(dynamic payload) {
  final body = payload is Map ? _asMap(payload) : const <String, dynamic>{};
  final cards = body["cards"];
  if (cards is! List) return const [];
  return [for (final card in cards) card.toString()];
}
