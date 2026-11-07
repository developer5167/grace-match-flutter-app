import 'package:flutter_bloc/flutter_bloc.dart';
import 'interests_event.dart';
import 'interests_state.dart';
import '../data/interests_repository.dart';

class InterestsBloc extends Bloc<InterestsEvent, InterestsState> {
  final InterestsRepository _repository;

  InterestsBloc(this._repository) : super(InterestsInitial()) {
    on<FetchInterestsEvent>(_onFetchInterests);
    on<InterestActionEvent>(_onInterestAction);
  }

  Future<void> _onFetchInterests(
    FetchInterestsEvent event,
    Emitter<InterestsState> emit,
  ) async {
    emit(InterestsLoading());
    try {
      final data = await _repository.fetchInterests();
      emit(
        InterestsLoaded(
          received: data['received']!,
          matches: data['matches']!,
          sent: data['sent']!,
        ),
      );
    } catch (e) {
      emit(InterestsError(e.toString()));
    }
  }

  Future<void> _onInterestAction(
    InterestActionEvent event,
    Emitter<InterestsState> emit,
  ) async {
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
      // Revert optimistic update on failure
      emit(current);
      emit(InterestsError(e.toString()));
    }
  }
}
