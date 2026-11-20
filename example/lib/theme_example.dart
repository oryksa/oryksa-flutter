// The "Colours and theme" code of the README, word for word. It is part of the example app, so CI compiles it
// (dart analyze + flutter build web) on every push, and the "theme" screen of the screenshots shows it.
import 'package:flutter/material.dart';
import 'package:oryksa/oryksa.dart';

/// Builds the two buttons of the README: your own colors (light) and the dark version with your accent.
List<Widget> readmeThemeExamples(OryksaClient client) => [
      // Your own colors (light)
      OryksaChatButton(
        client: client,
        theme: const OryksaChatTheme(accent: Color(0xFF0E8A6B)),
      ),

      // Dark version, with your accent
      OryksaChatButton(
        client: client,
        theme: const OryksaChatTheme.dark(accent: Color(0xFF3DD9A8)),
      ),
    ];

/// The theme of the "theme" screenshot.
const readmeTheme = OryksaChatTheme(accent: Color(0xFF0E8A6B));
