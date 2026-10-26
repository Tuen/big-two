import "package:big_two/online/game_api.dart";
import "package:big_two/rules/game.dart";
import "package:big_two/screens/online_page.dart";
import "package:big_two/screens/practice_page.dart";
import "package:big_two/theme.dart";
import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:supabase_flutter/supabase_flutter.dart";

const quickNames = ["Justin", "Mary", "Damien", "Pauline", "Siby", "Martina", "Francis"];

class HomePage extends StatefulWidget {
  final SharedPreferences prefs;
  final SupabaseClient? supabase;
  final String? initialCode;
  final double scale;
  final ValueChanged<double> onScale;
  const HomePage({
    super.key,
    required this.prefs,
    required this.supabase,
    required this.scale,
    required this.onScale,
    this.initialCode,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final TextEditingController _name;
  late final TextEditingController _code;
  late bool _sound;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.prefs.getString("playerName") ?? "");
    _code = TextEditingController(text: widget.initialCode ?? "");
    _sound = widget.prefs.getBool("sound") ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _saveLocal() async {
    await widget.prefs.setString("playerName", _name.text.trim());
    await widget.prefs.setBool("sound", _sound);
  }

  void _practice() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _needName();
      return;
    }
    _saveLocal();
    final others = quickNames.where((item) => item != name).take(3).toList();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PracticePage(
        names: [name, ...others],
        settings: defaultSettings,
        sound: _sound,
        testPreview: kTestPreview,
      ),
    )).then((_) => _reloadSound());
  }

  void _online({required bool create}) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _needName();
      return;
    }
    if (widget.supabase == null) {
      showDialog(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text("Online tables"),
          content: Text("This copy has no Supabase keys yet. You can still play on this device. The README explains how to connect a free project."),
        ),
      );
      return;
    }
    if (!create && _code.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter the table code.")));
      return;
    }
    _saveLocal();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OnlinePage(
        api: GameApi(widget.supabase!),
        name: name,
        create: create,
        code: _code.text.trim().toUpperCase(),
        sound: _sound,
      ),
    )).then((_) => _reloadSound());
  }

  void _reloadSound() {
    final stored = widget.prefs.getBool("sound") ?? true;
    if (mounted && stored != _sound) setState(() => _sound = stored);
  }

  void _needName() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter your name.")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text("Big Two", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800)),
            const Text("Four players. One deck. Your house rules.", style: TextStyle(fontSize: 18, color: Colors.white70)),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 22),
              decoration: const InputDecoration(labelText: "Your name", filled: true),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final name in quickNames)
                  ActionChip(
                    label: Text(name),
                    onPressed: () => setState(() => _name.text = name),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _practice, child: const Text("Play on this device")),
            const SizedBox(height: 20),
            const Text("Online table", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => _online(create: true), child: const Text("Create a table")),
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 22, letterSpacing: 4),
              decoration: const InputDecoration(labelText: "Table code", filled: true),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => _online(create: false), child: const Text("Join")),
            const SizedBox(height: 24),
            const Text("Text size", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            SegmentedButton<double>(
              segments: const [
                ButtonSegment(value: 1, label: Text("Normal")),
                ButtonSegment(value: 1.25, label: Text("Large")),
                ButtonSegment(value: 1.5, label: Text("Extra")),
              ],
              selected: {widget.scale},
              onSelectionChanged: (value) => widget.onScale(value.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _sound,
              title: const Text("Sounds"),
              onChanged: (value) async {
                setState(() => _sound = value);
                await widget.prefs.setBool("sound", value);
              },
            ),
            const SizedBox(height: 12),
            const Text(
              "A spade flush beats a heart flush, and a spade straight flush beats any heart straight flush. You cannot finish on 2s alone. A five-card hand may include a 2. If the next player has one card, a single must be your highest card. Bonuses are added to the other players as soon as they are played.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// True only for the GitHub Pages test preview (`--dart-define=TEST_PREVIEW=true`).
const kTestPreview = bool.fromEnvironment("TEST_PREVIEW");

class TestVersionBanner extends StatelessWidget {
  const TestVersionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Color(0xFFB71C1C),
      child: SizedBox(
        width: double.infinity,
        height: 28,
        child: Center(
          child: Text(
            "TEST VERSION · v1.5",
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1.4),
          ),
        ),
      ),
    );
  }
}

/// Floats the test banner over the app so it does not shrink the table.
class TestPreviewOverlay extends StatelessWidget {
  final bool show;
  final Widget child;
  const TestPreviewOverlay({super.key, required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      children: [
        child,
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: IgnorePointer(child: TestVersionBanner()),
          ),
        ),
      ],
    );
  }
}

class BigTwoApp extends StatefulWidget {
  final SharedPreferences prefs;
  final SupabaseClient? supabase;
  final String? initialCode;
  const BigTwoApp({super.key, required this.prefs, required this.supabase, this.initialCode});

  @override
  State<BigTwoApp> createState() => _BigTwoAppState();
}

class _BigTwoAppState extends State<BigTwoApp> {
  late double _scale;

  @override
  void initState() {
    super.initState();
    _scale = widget.prefs.getDouble("textScale") ?? 1;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kTestPreview ? "Big Two (test)" : "Big Two",
      theme: bigTwoTheme(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final system = MediaQuery.textScalerOf(context).scale(16) / 16;
        final scaled = MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(system * _scale)),
          child: child ?? const SizedBox.shrink(),
        );
        return TestPreviewOverlay(show: kTestPreview, child: scaled);
      },
      home: HomePage(
        prefs: widget.prefs,
        supabase: widget.supabase,
        initialCode: widget.initialCode,
        scale: _scale,
        onScale: (value) async {
          setState(() => _scale = value);
          await widget.prefs.setDouble("textScale", value);
        },
      ),
    );
  }
}
