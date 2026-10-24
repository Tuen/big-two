import "package:big_two/screens/home_page.dart";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  const url = String.fromEnvironment("SUPABASE_URL");
  const anonKey = String.fromEnvironment("SUPABASE_ANON_KEY");
  SupabaseClient? client;
  if (url.isNotEmpty && anonKey.isNotEmpty) {
    await Supabase.initialize(url: url, publishableKey: anonKey);
    client = Supabase.instance.client;
  }
  final code = Uri.base.queryParameters["code"];
  runApp(BigTwoApp(prefs: prefs, supabase: client, initialCode: code));
}
