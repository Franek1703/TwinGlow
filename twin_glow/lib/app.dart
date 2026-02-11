import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'config/app_theme.dart';
import 'config/app_router.dart';
import 'features/auth/cubit/auth_cubit.dart';
import 'services/firebase/firebase_repository_impl.dart';

class App extends StatelessWidget {
  const App({super.key});

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
            routerConfig: appRouter,
            debugShowCheckedModeBanner: false,
          ),
        );
      },
    );
  }
}
