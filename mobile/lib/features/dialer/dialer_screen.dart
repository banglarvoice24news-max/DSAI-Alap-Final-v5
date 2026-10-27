import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';
import '../settings/settings_cubit.dart';
import 'dialer_cubit.dart';

class DialerScreen extends StatefulWidget {
  const DialerScreen({super.key});

  @override
  State<DialerScreen> createState() => _DialerScreenState();
}

class _DialerScreenState extends State<DialerScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DialerCubit>().loadContacts();
  }

  Future<void> _maybePrompt(BuildContext context, DialerState state) async {
    if (!state.promptSimFallback) return;
    final l10n = AppLocalizations.of(context);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.dialerNoInternetTitle),
        content: Text(l10n.dialerNoInternetBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.dialerCancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l10n.dialerUseSim)),
        ],
      ),
    );
    if (!context.mounted) return;
    if (go == true) {
      await context.read<DialerCubit>().confirmSimCall();
    } else {
      context.read<DialerCubit>().dismissPrompt();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<DialerCubit, DialerState>(
      listenWhen: (p, c) => p.promptSimFallback != c.promptSimFallback && c.promptSimFallback,
      listener: _maybePrompt,
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(l10n.dialerTitle)),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  state.digits.isEmpty ? ' ' : state.digits,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 3,
                  childAspectRatio: 1.6,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  children: [
                    for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'])
                      TextButton(
                        onPressed: () => context.read<DialerCubit>().pushDigit(d),
                        child: Text(d, style: Theme.of(context).textTheme.headlineSmall),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    onPressed: () => context.read<DialerCubit>().backspace(),
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final prio = context.read<SettingsCubit>().state.priority;
                      context.read<DialerCubit>().placeCall(prio);
                    },
                    icon: const Icon(Icons.call),
                    label: Text(l10n.dialerCall),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ExpansionTile(
                title: Text(l10n.dialerContacts),
                children: [
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: state.contacts.length,
                      itemBuilder: (context, i) {
                        final c = state.contacts[i];
                        return ListTile(
                          dense: true,
                          title: Text(c.name),
                          subtitle: Text(c.phone),
                          onTap: () => context.read<DialerCubit>().setNumber(c.phone),
                        );
                      },
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
