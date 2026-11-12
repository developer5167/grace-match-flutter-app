import 'package:flutter_bloc/flutter_bloc.dart';
import 'interests_event.dart';
import 'interests_state.dart';
import '../data/interests_repository.dart';

class InterestsBloc extends Bloc<InterestsEvent, InterestsState> {
  final InterestsRepository _repository;
  bool _fetching = false;
  // Bumped by every accept/decline. A fetch that started before one would
  // put the answered interest back on screen, so its result is dropped.
  int _actionSeq = 0;

  InterestsBloc(this._repository) : super(InterestsInitial()) {
    on<FetchInterestsEvent>(_onFetchInterests);
    on<InterestActionEvent>(_onInterestAction);
  }

  Future<void> _onFetchInterests(
    FetchInterestsEvent event,
    Emitter<InterestsState> emit,
  ) async {
    // One request at a time; a second open or pull while one is out would
    // only fetch the same lists again.
    if (_fetching) return;
    _fetching = true;
    // Lists already on screen stay there while they refresh.
    final hadData = state is InterestsLoaded;
    if (!hadData) emit(InterestsLoading());
    final seq = _actionSeq;
    try {
      final data = await _repository.fetchInterests();
      if (seq != _actionSeq && state is InterestsLoaded) return;
      emit(
        InterestsLoaded(
          received: data['received']!,
          matches: data['matches']!,
          sent: data['sent']!,
        ),
      );
    } catch (e) {
      // A failed refresh keeps the lists the member was looking at.
      if (!(hadData && state is InterestsLoaded)) {
        emit(InterestsError(e.toString()));
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _onInterestAction(
    InterestActionEvent event,
    Emitter<InterestsState> emit,
  ) async {
    _actionSeq++;
    if (state is! InterestsLoaded) {
      // No cached state — fall back to full re-fetch
      try {
        await _repository.handleAction(event.interestId, accept: event.accept);
        add(FetchInterestsEvent());
      } catch (e) {
        emit(InterestsError(e.toString()));
      }
      return;
    }

    final current = state as InterestsLoaded;

    // Find the item in received before removing it
    final item = current.received.firstWhere(
      (i) => i['interest_id']?.toString() == event.interestId,
      orElse: () => {},
    );

    // Optimistically remove from received list right away (instant UI feedback)
    final updatedReceived = current.received
        .where((i) => i['interest_id']?.toString() != event.interestId)
        .toList();
    emit(
      InterestsLoaded(
        received: updatedReceived,
        matches: current.matches,
        sent: current.sent,
      ),
    );

    try {
      final result = await _repository.handleAction(
        event.interestId,
        accept: event.accept,
      );

      if (event.accept && item.isNotEmpty) {
        // Move accepted item to matches, embedding conversation_id from backend response
        final convId = result?['conversation_id'];
        final matchEntry = <String, dynamic>{
          ...item,
          'status': 'accepted',
          if (convId != null) 'conversation_id': convId,
        };
        emit(
          InterestsLoaded(
            received: updatedReceived,
            matches: [matchEntry, ...current.matches],
            sent: current.sent,
          ),
        );
      }
      // For reject: updatedReceived is already emitted above, nothing else needed
    } catch (e) {
      // Put the item back and say why, without replacing the tabs with an
      // error screen.
      emit(
        InterestsLoaded(
          received: current.received,
          matches: current.matches,
          sent: current.sent,
          actionError: e.toString().replaceFirst('Exception: ', ''),
        ),
      );
    }
  }
}
