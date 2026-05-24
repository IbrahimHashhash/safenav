import 'package:flutter/material.dart';

abstract class TtsService {
  Future<void> speak(String text, {VoidCallback? onComplete});
  Future<void> stop();
}