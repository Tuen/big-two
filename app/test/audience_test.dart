import "package:big_two/online/audience.dart";
import "package:big_two/widgets/full_table_prompt.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("chat is short, unread is only what is new, and a watcher cannot act", () {
    expect(rejectedChat("  "), "Enter a message");
    expect(rejectedChat("n" * 201), "Keep it to 200 characters");
    expect(rejectedChat("  see you  "), isNull);
    expect(cleanedChat("  see   you "), "see you");
    expect(unreadChat([1, 2, 4], 2), 1);
    expect(unreadChat([1, 2], null), 0);
    expect(watcherCanAct(watching: true, yourTurn: true, allowed: true), isFalse);
    expect(watcherCanAct(watching: false, yourTurn: true, allowed: true), isTrue);
    expect(watcherCanAct(watching: false, yourTurn: false, allowed: true), isFalse);
  });

  testWidgets("a full table offers Watch this game and Cancel", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: FullTablePrompt(message: "That table is full")));
    expect(find.text("That table is full"), findsOneWidget);
    expect(find.text("Watch this game"), findsOneWidget);
    expect(find.text("Cancel"), findsOneWidget);
  });
}
