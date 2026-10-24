import "package:flutter/material.dart";

const felt = Color(0xFF0C5C38);
const feltDeep = Color(0xFF083D26);
const cardFace = Color(0xFFFFFBF5);
const cardRed = Color(0xFFC4161C);
const ink = Color(0xFF1A1A1A);
const gold = Color(0xFFE2B340);
const goldDeep = Color(0xFF8A6A12);

ThemeData bigTwoTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: felt, brightness: Brightness.dark, primary: gold, surface: feltDeep),
    scaffoldBackgroundColor: felt,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(148, 60),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        backgroundColor: gold,
        foregroundColor: ink,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(148, 60),
        textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
        side: const BorderSide(color: Colors.white, width: 2),
      ),
    ),
  );
}
