const chatLimit = 200;

/// Empty when the text can be sent. Otherwise the reason it cannot.
String? rejectedChat(String raw) {
  final text = raw.replaceAll(RegExp(r"\s+"), " ").trim();
  if (text.isEmpty) return "Enter a message";
  if (text.length > chatLimit) return "Keep it to 200 characters";
  return null;
}

String cleanedChat(String raw) => raw.replaceAll(RegExp(r"\s+"), " ").trim();

/// Messages already on screen when you arrived are not unread.
int unreadChat(List<int> ids, int? seen) {
  if (seen == null) return 0;
  return ids.where((id) => id > seen).length;
}

/// A watcher cannot play, pass, or vote, and is not shown a hand.
bool watcherCanAct({required bool watching, required bool yourTurn, required bool allowed}) {
  return !watching && yourTurn && allowed;
}

/// "Watching: Ralph, Ada", in the order they started. Null when nobody is watching.
String? watchingLine(List<String> names) {
  if (names.isEmpty) return null;
  return "Watching: ${names.join(", ")}";
}

/// Older servers only sent a count. Prefer the names when we have them.
String? audienceLabel({required List<String> names, required int count}) {
  final line = watchingLine(names);
  if (line != null) return line;
  if (count == 1) return "1 watching";
  if (count > 1) return "$count watching";
  return null;
}
