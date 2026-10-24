import "package:big_two/theme.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("the theme can be built", () {
    final theme = bigTwoTheme();
    expect(theme.scaffoldBackgroundColor, felt);
    expect(theme.textTheme.bodyMedium?.color, isNotNull);
  });
}
