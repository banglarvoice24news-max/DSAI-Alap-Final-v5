import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../hybrid/hybrid_models.dart';
import 'calls_repository.dart';

class CallsState extends Equatable {
  const CallsState({this.calls = const [], this.loading = false});

  final List<CallRecord> calls;
  final bool loading;

  @override
  List<Object?> get props => [calls, loading];
}

class CallsCubit extends Cubit<CallsState> {
  CallsCubit({CallLogRepository? repository})
      : _repo = repository ?? CpaasCallLogRepository(),
        super(const CallsState());

  final CallLogRepository _repo;

  Future<void> load() async {
    emit(const CallsState(loading: true));
    try {
      emit(CallsState(calls: await _repo.loadCalls()));
    } catch (_) {
      // TODO(P2-CALLS-ERROR): surface auth/network failure distinctly from an
      // empty history once the Calls tab has an error affordance.
      emit(const CallsState(calls: []));
    }
  }
}
