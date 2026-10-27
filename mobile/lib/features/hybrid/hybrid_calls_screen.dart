// Calls tab — transport-tagged history + favorites (first-pass prototype).
//
// Redial pushes the InCallScreen prototype. Dialing still honours the stored
// fallback preference (SettingsCubit.priority) once the real router exists;
// for now the in-call screen simulates the Mesh -> VoIP -> GSM handoff so the
// fallback moment is visible in the UI (GAP NOTE in in_call_screen.dart).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../calls/calls_cubit.dart';
import '../settings/connection_priority.dart';
import '../settings/settings_cubit.dart';
import 'hybrid_models.dart';
import 'in_call_screen.dart';
import 'widgets/transport_ui.dart';

class HybridCallsScreen extends StatefulWidget {
  const HybridCallsScreen({super.key});

  @override
  State<HybridCallsScreen> createState() => _HybridCallsScreenState();
}

class _HybridCallsScreenState extends State<HybridCallsScreen> {
  @override
  void initState() {
    super.initState();
    context.read<CallsCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      body: SafeArea(
        child: BlocBuilder<CallsCubit, CallsState>(
          builder: (context, state) {
            if (state.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            // TODO(P2-CALLS-EMPTY): dedicated localized empty-calls copy once
            // the l10n shim is extended (do not add strings here).
            if (state.calls.isEmpty) {
              return const Center(child: Icon(Icons.call_outlined, size: 48, color: AppTokens.textSecondary));
            }
            final favorites = state.calls.where((c) => c.favorite).toList();
            final recents = state.calls.where((c) => !c.favorite).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                if (favorites.isNotEmpty) ...[
                  _SectionLabel(AppStrings.callsFavorites),
                  const SizedBox(height: 8),
                  for (final c in favorites) _CallTile(call: c),
                  const SizedBox(height: 16),
                ],
                _SectionLabel(AppStrings.callsRecents),
                const SizedBox(height: 8),
                for (final c in recents) _CallTile(call: c),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTokens.primaryBright,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.dialpad),
        label: const Text(AppStrings.callsKeypad),
        onPressed: () => _openNewCallSheet(context),
      ),
    );
  }

  void _openNewCallSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTokens.surface,
      builder: (sheetCtx) => _NewCallSheet(),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: AppTokens.textSecondary),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({required this.call});
  final CallRecord call;

  @override
  Widget build(BuildContext context) {
    final color = transportColor(call.transport);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.2),
            child: Icon(
              call.missed ? Icons.call_missed_outlined : Icons.call_outlined,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(call.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  call.missed
                      ? '${AppStrings.callMissed} • ${call.number}'
                      : (call.durationSec == null
                          ? call.number
                          : '${call.number} • ${_fmt(call.durationSec!)}'),
                  style: const TextStyle(fontSize: 12.5, color: AppTokens.textSecondary),
                ),
              ],
            ),
          ),
          TransportChip(transport: call.transport, dim: true),
          const SizedBox(width: 4),
          IconButton(
            tooltip: AppStrings.redial,
            color: call.missed ? AppTokens.danger : AppTokens.primaryBright,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => InCallScreen(contactName: call.name, number: call.number)),
              );
            },
            icon: const Icon(Icons.call_outlined),
          ),
        ],
      ),
    );
  }

  String _fmt(int sec) {
    final m = (sec ~/ 60).toString();
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _NewCallSheet extends StatefulWidget {
  @override
  State<_NewCallSheet> createState() => _NewCallSheetState();
}

class _NewCallSheetState extends State<_NewCallSheet> {
  final TextEditingController _number = TextEditingController();
  ConnectionPriority _priority = ConnectionPriority.auto;

  @override
  void initState() {
    super.initState();
    _priority = context.read<SettingsCubit>().state.priority;
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  void _call(BuildContext context) {
    final digits = _number.text.trim();
    if (digits.isEmpty) return;
    Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InCallScreen(contactName: digits, number: digits),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.callNow, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: _number,
              keyboardType: TextInputType.phone,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '+8801XXXXXXXXX',
                filled: true,
                fillColor: AppTokens.canvas,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Text(AppStrings.settingsRoutePref, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
            const SizedBox(height: 6),
            SegmentedButton<ConnectionPriority>(
              segments: const [
                ButtonSegment(value: ConnectionPriority.auto, label: Text(AppStrings.settingsAuto)),
                ButtonSegment(value: ConnectionPriority.meshOnly, label: Text(AppStrings.settingsMeshOnly)),
                ButtonSegment(value: ConnectionPriority.simOnly, label: Text(AppStrings.settingsGsmOnly)),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.primaryBright,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _call(context),
                icon: const Icon(Icons.call),
                label: const Text(AppStrings.callNow, style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
