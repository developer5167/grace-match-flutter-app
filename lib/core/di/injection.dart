import 'package:get_it/get_it.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/bloc/auth_bloc.dart';
import '../../features/onboarding/data/onboarding_repository.dart';
import '../../features/onboarding/bloc/onboarding_bloc.dart';
import '../../features/discover/data/discover_repository.dart';
import '../../features/discover/bloc/discover_bloc.dart';
import '../../features/interests/data/interests_repository.dart';
import '../../features/interests/bloc/interests_bloc.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/bloc/profile_bloc.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/chat/bloc/chat_bloc.dart';
import '../network/socket_service.dart';
import '../../features/subscriptions/data/subscription_repository.dart';
import '../../features/subscriptions/bloc/subscription_bloc.dart';
import '../../features/activity/data/activity_repository.dart';
import '../../features/activity/bloc/activity_bloc.dart';

final sl = GetIt.instance;

void init() {
  // Services
  sl.registerLazySingleton<SocketService>(() => SocketService());

  // Repositories
  sl.registerLazySingleton<AuthRepository>(() => AuthRepository());
  sl.registerLazySingleton<OnboardingRepository>(() => OnboardingRepository());
  sl.registerLazySingleton<DiscoverRepository>(() => DiscoverRepository());
  sl.registerLazySingleton<InterestsRepository>(() => InterestsRepository());
  sl.registerLazySingleton<ProfileRepository>(() => ProfileRepository());
  sl.registerLazySingleton<ChatRepository>(() => ChatRepository());
  sl.registerLazySingleton<SubscriptionRepository>(() => SubscriptionRepository());
  sl.registerLazySingleton<ActivityRepository>(() => ActivityRepository());

  // BLoCs
  sl.registerFactory(() => AuthBloc(sl(), sl()));
  sl.registerFactory(() => OnboardingBloc(sl()));
  sl.registerFactory(() => DiscoverBloc(sl()));
  sl.registerFactory(() => InterestsBloc(sl()));
  sl.registerFactory(() => ProfileBloc(sl()));
  sl.registerFactory(() => ChatBloc(sl(), sl()));
  sl.registerFactory(() => SubscriptionBloc(sl()));
  sl.registerFactory(() => ActivityBloc(sl()));
}
