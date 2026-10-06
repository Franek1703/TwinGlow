import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/pairing/cubit/shared_screens_cubit.dart';
import '../../services/firebase/firebase_repository.dart';
import 'app_card.dart';
import 'screen_preview.dart';

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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              'Shared with you',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text('Preview your partner’s shared default content.'),
            if (state.isLoading) const LinearProgressIndicator(),
            if (state.error != null) ...[
              const Text('Could not synchronize shared screens.'),
              TextButton(
                onPressed: () => context.read<SharedScreensCubit>().retry(),
                child: const Text('Retry'),
              ),
            ],
            if (!state.isLoading &&
                state.error == null &&
                state.screens.isEmpty)
              const Text('Your partner has not shared any screens yet.'),
            for (final screen in state.screens)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        screen.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: ScreenPreview(
                          screen: screen.previewScreen,
                          assets: [screen.asset],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}
