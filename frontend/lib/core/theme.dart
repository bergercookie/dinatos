import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) => ThemeData(
  brightness: brightness,
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange, brightness: brightness),
  useMaterial3: true,
);
