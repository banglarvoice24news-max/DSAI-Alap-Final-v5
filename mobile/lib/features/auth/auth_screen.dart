import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';
import '../../offline_slice1/presentation/offline_nearby_screen.dart';
import 'auth_cubit.dart';
import 'auth_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _backup = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _backup.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: BlocBuilder<AuthCubit, AuthState>(
          builder: (context, state) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  Text(l10n.appName, style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 8),
                  Text(l10n.otpHint),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    enableIMEPersonalizedLearning: false,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.phone),
                      labelText: '+8801XXXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (state.status == AuthStatus.codeSent)
                    TextField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      enableIMEPersonalizedLearning: false,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.sms),
                        labelText: 'OTP',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      if (state.status == AuthStatus.codeSent) {
                        context.read<AuthCubit>().verifyOtp(
                              _otp.text.trim(),
                              publicKey: 'pending-identity-key',
                            );
                      } else {
                        context.read<AuthCubit>().requestOtp(_phone.text.trim());
                      }
                    },
                    child: Text(state.status == AuthStatus.codeSent ? l10n.otpVerify : l10n.otpSend),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => context.read<AuthCubit>().continueOffline(),
                    child: const Text('Continue nearby without account'),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _backup,
                    enableSuggestions: false,
                    autocorrect: false,
                    enableIMEPersonalizedLearning: false,
                    smartDashesType: SmartDashesType.disabled,
                    smartQuotesType: SmartQuotesType.disabled,
                    decoration: InputDecoration(
                      labelText: l10n.settingsE2eeVerify,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => context.read<AuthCubit>().restoreWithBackup(
                          _phone.text.trim(),
                          _backup.text.trim(),
                        ),
                    child: const Text('Restore from offline backup key'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const OfflineNearbyScreen(),
                        ),
                      );
                    },
                    child: const Text('Use offline nearby without OTP'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
