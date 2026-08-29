import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'config/app_theme.dart';
import 'config/app_router.dart';
import 'features/auth/cubit/auth_cubit.dart';
import 'services/firebase/firebase_repository_impl.dart';
import 'services/local/onboarding_status_store.dart';

class App extends StatefulWidget {
  final OnboardingStatusStore onboardingStatusStore;

  const App({super.key, required this.onboardingStatusStore});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final _router = createAppRouter(widget.onboardingStatusStore);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // iPhone X size
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return BlocProvider(
          create: (_) => AuthCubit(FirebaseRepositoryImpl()),
          child: MaterialApp.router(
            title: 'TwinGlow',
            theme: AppTheme.darkTheme,
            routerConfig: _router,
            debugShowCheckedModeBanner: false,
          ),
        );
      },
    );
  }
}
