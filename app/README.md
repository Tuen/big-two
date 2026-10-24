# Big Two app

This is the Flutter web app. How to run it, test it, build it, and deploy the server is in the parent [README](../README.md). The house rules are in [RULES](../RULES.md).

```powershell
flutter pub get
flutter test
flutter run -d chrome --dart-define-from-file=public-client.json
```

The web app is the only target. Android and iOS project folders are not part of the published source.
