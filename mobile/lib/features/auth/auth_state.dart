import 'package:equatable/equatable.dart';

enum AuthStatus { unknown, unauthenticated, codeSent, authenticated }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.unknown,
    this.phone = '',
    this.message,
  });

  final AuthStatus status;
  final String phone;
  final String? message;

  AuthState copyWith({AuthStatus? status, String? phone, String? message}) {
    return AuthState(
      status: status ?? this.status,
      phone: phone ?? this.phone,
      message: message,
    );
  }

  @override
  List<Object?> get props => [status, phone, message];
}
