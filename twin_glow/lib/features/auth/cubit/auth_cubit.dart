import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/models/user_model.dart';
import '../../../services/firebase/firebase_repository.dart';

class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;

  AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => user != null;

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class AuthCubit extends Cubit<AuthState> {
  final FirebaseRepository firebaseRepository;

  AuthCubit(this.firebaseRepository) : super(AuthState()) {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    emit(state.copyWith(isLoading: true));
    try {
      final user = await firebaseRepository.getCurrentUser();
      emit(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> signIn(String email, String password) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final user = await firebaseRepository.signIn(email, password);
      emit(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> signUp(String email, String password) async {
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final user = await firebaseRepository.signUp(email, password);
      emit(state.copyWith(user: user, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> signOut() async {
    emit(state.copyWith(isLoading: true));
    try {
      await firebaseRepository.signOut();
      emit(state.copyWith(user: null, isLoading: false));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }
}
