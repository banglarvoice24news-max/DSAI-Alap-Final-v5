import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/dsaialap_glass.dart';
import '../settings/connection_priority.dart';
import '../settings/settings_cubit.dart';
import 'dialer_cubit.dart';

class SmartDialerScreen extends StatefulWidget {
  const SmartDialerScreen({super.key});

  @override
  State<SmartDialerScreen> createState() => _SmartDialerScreenState();
}

class _SmartDialerScreenState extends State<SmartDialerScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    context.read<DialerCubit>().loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocConsumer<DialerCubit, DialerState>(
      listenWhen: (p, c) => p.promptSimFallback != c.promptSimFallback && c.promptSimFallback,
      listener: (context, state) async {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: DsaialapTokens.oled,
            title: const Text('No Internet'),
            content: const Text('Fall back to SIM card?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Call via SIM')),
            ],
          ),
        );
        if (!context.mounted) return;
        if (go == true) {
          await context.read<DialerCubit>().confirmSimCall();
        } else {
          context.read<DialerCubit>().dismissPrompt();
        }
      },
      builder: (context, state) {
        final settings = context.watch<SettingsCubit>().state;
        final viaSim = settings.priority == ConnectionPriority.simOnly;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              GlassCard(
                child: Column(
                  children: [
                    Text(
                      state.digits.isEmpty ? 'Enter number' : state.digits,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('VoIP / Mesh'), icon: Icon(Icons.wifi_tethering)),
                        ButtonSegment(value: true, label: Text('Call via SIM'), icon: Icon(Icons.sim_card)),
                      ],
                      selected: {viaSim},
                      onSelectionChanged: (s) {
                        context.read<SettingsCubit>().setPriority(
                              s.first ? ConnectionPriority.simOnly : ConnectionPriority.auto,
                            );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  childAspectRatio: 1.35,
                  children: [
                    for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: GlassCard(
                          padding: EdgeInsets.zero,
                          child: InkWell(
                            onTap: () => context.read<DialerCubit>().pushDigit(d),
                            child: Center(
                              child: Text(d, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () => context.read<DialerCubit>().backspace(),
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: viaSim ? DsaialapTokens.neonOrange : DsaialapTokens.neonLime,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () => context.read<DialerCubit>().placeCall(settings.priority),
                      icon: const Icon(Icons.call),
                      label: Text(viaSim ? 'SIM CALL' : 'VOIP / MESH CALL'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
