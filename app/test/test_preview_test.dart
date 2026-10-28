import "package:big_two/screens/home_page.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  testWidgets("the test build shows TEST VERSION and the live build does not", (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: TestPreviewOverlay(show: true, child: SizedBox.shrink()),
    ));
    expect(find.text("TEST VERSION · v1.7"), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: TestPreviewOverlay(show: false, child: Text("live")),
    ));
    expect(find.text("TEST VERSION"), findsNothing);
    expect(find.text("live"), findsOneWidget);
  });
}
