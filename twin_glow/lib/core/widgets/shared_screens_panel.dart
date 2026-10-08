import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/pairing/cubit/shared_screens_cubit.dart';
import '../../services/firebase/firebase_repository.dart';

class SharedScreensPanel extends StatelessWidget {
  final FirebaseRepository repository;
  final String userId;
  final String? deviceId;
  const SharedScreensPanel({
    super.key,
    required this.repository,
    required this.userId,
    this.deviceId,
  });

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(userId),
    create: (_) => SharedScreensCubit(repository, userId),
    child: BlocBuilder<SharedScreensCubit, SharedScreensState>(
      builder: (context, state) {
        if (!state.pairing.isPaired ||
            (deviceId != null && state.pairing.deviceId != deviceId)) {
          return const SizedBox.shrink();
        }
        if (state.error == null) return const SizedBox.shrink();
        return TextButton(
          onPressed: () => context.read<SharedScreensCubit>().retry(),
          child: const Text('Retry shared screen setup'),
        );
      },
    ),
  );
}
