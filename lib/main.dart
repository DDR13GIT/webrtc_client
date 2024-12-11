import 'package:flutter/material.dart';
import 'screens/call_screen.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: Colors.green,
      brightness: Brightness.light,
      textTheme: GoogleFonts.robotoTextTheme(),
    ),
    themeMode: ThemeMode.light, // Force light theme
    home: CallScreen(),
  ));
}