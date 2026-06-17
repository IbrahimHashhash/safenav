import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safenav_app/features/voice_interaction/presentation/widgets/idle_view.dart';
import 'package:safenav_app/features/voice_interaction/presentation/widgets/listening_view.dart';
import 'package:safenav_app/features/voice_interaction/presentation/widgets/speaking_view.dart';
import 'package:safenav_app/features/voice_interaction/presentation/widgets/sound_wave.dart';

void main() {
  testWidgets('IdleView renders dots and prompt', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: IdleView())));
    expect(find.text('Hold anywhere to speak'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ListeningView renders waveform and label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ListeningView())));
    expect(find.byType(SoundWave), findsOneWidget);
    expect(find.text('Listening...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SpeakingView renders waveform and label', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SpeakingView())));
    expect(find.byType(SoundWave), findsOneWidget);
    expect(find.text('Speaking...'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
