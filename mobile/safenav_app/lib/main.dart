import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/di/injection.dart';

import 'features/voice_interaction/presentation/cubit/voice_assistant_cubit.dart';

import 'features/voice_interaction/presentation/pages/voice_assistant_page.dart';

void main() async {

  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');  
  await initDependencies();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {

    return MultiBlocProvider(

      providers: [

        BlocProvider(

          create: (_) => VoiceAssistantCubit(
            sttService: sl(),
            ttsService: sl(),
            intentParser: sl(),
            locationExtractor: sl(),
          ),
        ),
      ],

      child: MaterialApp(

        debugShowCheckedModeBanner: false,

        theme: ThemeData.dark(),

        home: const VoiceAssistantPage(),
      ),
    );
  }
}