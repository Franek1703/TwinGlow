import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../config/app_colors.dart';
import '../../core/models/device_model.dart';
import '../../core/models/pairing_model.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_input.dart';
import '../../core/widgets/shared_screens_panel.dart';
import '../../features/auth/cubit/auth_cubit.dart';
import '../../features/pairing/cubit/pairing_cubit.dart';
import '../../services/firebase/firebase_repository.dart';
import '../../services/firebase/firebase_repository_impl.dart';

class PairingManagementView extends StatefulWidget {
  final FirebaseRepository? repository;
  const PairingManagementView({super.key, this.repository});
  @override
  State<PairingManagementView> createState() => _PairingManagementViewState();
}

class _PairingManagementViewState extends State<PairingManagementView> {
  final _email = TextEditingController();
  String? _deviceId;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthCubit>().state.user?.id;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return BlocProvider(
      key: ValueKey(uid),
      create: (_) =>
          PairingCubit(widget.repository ?? FirebaseRepositoryImpl(), uid),
      child: Scaffold(
        backgroundColor: AppColors.bgPrimary,
        appBar: AppBar(title: const Text('Pairing Management')),
        body: BlocBuilder<PairingCubit, PairingState>(
          builder: (context, state) {
            if (state.isInitialLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final selected = state.devices.any((d) => d.id == _deviceId)
                ? _deviceId
                : (state.devices.length == 1 ? state.devices.first.id : null);
            final cubit = context.read<PairingCubit>();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (state.error != null) ...[
                  Text(
                    state.error!,
                    key: const Key('pairing-error'),
                    style: const TextStyle(color: AppColors.statusError),
                  ),
                  TextButton(
                    onPressed: state.isBusy ? null : cubit.loadPairing,
                    child: const Text('Retry'),
                  ),
                ],
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.pairing.isPaired
                            ? 'Paired with ${state.pairing.pairedUserName}'
                            : 'Not paired',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (state.pairing.isPaired) ...[
                        Text(
                          '${state.pairing.deviceId} ↔ ${state.pairing.partnerDeviceId}',
                        ),
                        const Text(
                          'Shared screens appear in both playlists and both people can edit them. Hold ACTION to send the currently displayed content.',
                        ),
                        if (state.acknowledgment['status'] != null)
                          Text(
                            'Partner last acknowledgment: ${state.acknowledgment['status']}',
                          ),
                        AppButton(
                          text: 'Unpair',
                          isLoading: state.isBusy,
                          variant: AppButtonVariant.danger,
                          onPressed: () => _unpair(context, cubit),
                        ),
                      ],
                    ],
                  ),
                ),
                if (state.pairing.isPaired)
                  SharedScreensPanel(
                    repository: cubit.firebaseRepository,
                    userId: uid,
                  ),
                if (!state.pairing.isPaired) ...[
                  const SizedBox(height: 20),
                  _selector(state.devices, selected, state.isBusy),
                  if (state.devices.isEmpty)
                    const Text(
                      'No enrolled devices. Finish device setup before pairing.',
                    ),
                  AppInput(
                    controller: _email,
                    label: 'Partner email',
                    hint: 'user@example.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  AppButton(
                    text: 'Send Invite',
                    isLoading: state.isBusy,
                    onPressed: selected == null
                        ? null
                        : () async {
                            final email = _email.text.trim();
                            if (email.isEmpty) return;
                            final ok = await cubit.sendInvite(email, selected);
                            if (!context.mounted) return;
                            if (ok) {
                              _email.clear();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Invite sent to $email'),
                                ),
                              );
                            }
                          },
                  ),
                ],
                const SizedBox(height: 20),
                ...state.incoming
                    .where((i) => i.isPending)
                    .map(
                      (i) => _invite(context, i, true, selected, state, cubit),
                    ),
                ...state.outgoing
                    .where((i) => i.isPending)
                    .map(
                      (i) => _invite(context, i, false, selected, state, cubit),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _selector(List<DeviceModel> devices, String? selected, bool busy) =>
      DropdownButtonFormField<String>(
        key: ValueKey('pair-device-$selected'),
        initialValue: selected,
        decoration: const InputDecoration(labelText: 'Your device'),
        items: devices
            .map(
              (d) => DropdownMenuItem(
                value: d.id,
                child: Text(d.name.isEmpty ? d.id : d.name),
              ),
            )
            .toList(),
        onChanged: busy ? null : (id) => setState(() => _deviceId = id),
      );
  Widget _invite(
    BuildContext context,
    PairingInvite i,
    bool incoming,
    String? selected,
    PairingState state,
    PairingCubit cubit,
  ) {
    final expired = i.isExpired(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              incoming
                  ? 'Invitation from ${i.fromEmail}'
                  : 'Invitation to ${i.toEmail}',
            ),
            Text(expired ? 'Expired' : 'Waiting for acceptance'),
            if (incoming && !expired && !state.pairing.isPaired)
              AppButton(
                text: 'Accept',
                isLoading: state.isBusy,
                onPressed: selected == null
                    ? null
                    : () => cubit.acceptInvite(i.id, selected),
              ),
            TextButton(
              onPressed: state.isBusy
                  ? null
                  : () => cubit.resolveInvite(
                      i.id,
                      expired
                          ? 'expired'
                          : (incoming ? 'rejected' : 'cancelled'),
                    ),
              child: Text(
                expired ? 'Dismiss' : (incoming ? 'Reject' : 'Cancel invite'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _unpair(BuildContext context, PairingCubit cubit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unpair devices?'),
        content: const Text(
          'This stops sharing. Your local screens and assets are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Unpair'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.unpair();
  }
}
