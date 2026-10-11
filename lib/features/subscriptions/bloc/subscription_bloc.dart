import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../data/subscription_repository.dart';

// ─── Events ──────────────────────────────────────────────────
abstract class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();
  @override
  List<Object?> get props => [];
}

class FetchPlansEvent extends SubscriptionEvent {}

class InitiatePaymentEvent extends SubscriptionEvent {
  final Map<String, dynamic> plan;

  /// Priced by the server, not here. The sheet must open on the amount the
  /// server will actually charge.
  final String? couponCode;

  const InitiatePaymentEvent(this.plan, {this.couponCode});
}

class PaymentSuccessEvent extends SubscriptionEvent {
  final PaymentSuccessResponse response;
  const PaymentSuccessEvent(this.response);
}

class PaymentErrorEvent extends SubscriptionEvent {
  final PaymentFailureResponse response;
  const PaymentErrorEvent(this.response);
}

// ─── States ──────────────────────────────────────────────────
abstract class SubscriptionState extends Equatable {
  const SubscriptionState();
  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {}
class SubscriptionLoading extends SubscriptionState {}
class PlansLoaded extends SubscriptionState {
  final List<Map<String, dynamic>> plans;
  const PlansLoaded(this.plans);
}
class PaymentPending extends SubscriptionState {}
class PaymentProcessed extends SubscriptionState {
  final bool success;
  final String? message;
  const PaymentProcessed({required this.success, this.message});
}
class SubscriptionError extends SubscriptionState {
  final String message;
  const SubscriptionError(this.message);
}

// ─── BLoC ────────────────────────────────────────────────────
class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  final SubscriptionRepository _repository;
  final Razorpay _razorpay = Razorpay();
  String? _lastOrderId;

  SubscriptionBloc(this._repository) : super(SubscriptionInitial()) {
    on<FetchPlansEvent>(_onFetchPlans);
    on<InitiatePaymentEvent>(_onInitiatePayment);
    on<PaymentSuccessEvent>(_onPaymentSuccess);
    on<PaymentErrorEvent>(_onPaymentError);

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  Future<void> _onFetchPlans(FetchPlansEvent event, Emitter<SubscriptionState> emit) async {
    emit(SubscriptionLoading());
    try {
      final plans = await _repository.fetchPlans();
      emit(PlansLoaded(plans));
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _onInitiatePayment(InitiatePaymentEvent event, Emitter<SubscriptionState> emit) async {
    emit(PaymentPending());
    try {
      final orderData = await _repository.createOrder(
        event.plan['id'],
        couponCode: event.couponCode,
      );
      final rupees = orderData['amount'];
      final amountPaise = ((rupees is num)
              ? rupees.toDouble()
              : double.parse(rupees.toString())) *
          100;
      final options = <String, dynamic>{
        'key': orderData['key']?.toString() ?? '',
        'amount': amountPaise.round(),
        'currency': 'INR',
        'name': 'GraceMatch Premium',
        'order_id': orderData['order_id']?.toString() ?? '',
        'description': event.plan['name']?.toString() ?? 'Premium',
        'timeout': 300,
      };
      final prefill = <String, dynamic>{};
      final contact = orderData['contact']?.toString().trim() ?? '';
      final payerName = orderData['name']?.toString().trim() ?? '';
      final email = orderData['email']?.toString().trim() ?? '';
      if (contact.isNotEmpty) prefill['contact'] = contact;
      if (payerName.isNotEmpty) prefill['name'] = payerName;
      if (email.isNotEmpty) prefill['email'] = email;
      if (prefill.isNotEmpty) options['prefill'] = prefill;

      if (options['key'] == null || (options['key'] as String).isEmpty) {
        throw Exception('Razorpay key missing. Set RAZORPAY_KEY_ID on the server.');
      }
      if ((options['order_id'] as String).isEmpty) {
        throw Exception('Could not create payment order.');
      }

      _lastOrderId = options['order_id'] as String;
      _razorpay.open(options);
    } catch (e) {
      emit(SubscriptionError(e.toString()));
    }
  }

  Future<void> _onPaymentSuccess(
      PaymentSuccessEvent event, Emitter<SubscriptionState> emit) async {
    // Verify payment signature on the server to activate the subscription.
    try {
      final verified = await _repository.verifyPayment(
        orderId: event.response.orderId ?? '',
        paymentId: event.response.paymentId ?? '',
        signature: event.response.signature ?? '',
      );
      if (verified) {
        emit(const PaymentProcessed(
            success: true,
            message: '🎉 Premium Activated! Enjoy unlimited matches.'));
      } else {
        emit(const PaymentProcessed(
            success: false,
            message: 'Payment verification failed. Contact support if amount was deducted.'));
      }
    } catch (_) {
      // Even if verify call fails, the webhook will activate it.
      emit(const PaymentProcessed(
          success: true,
          message: 'Payment received! Your subscription will activate shortly.'));
    }
  }

  Future<void> _onPaymentError(PaymentErrorEvent event, Emitter<SubscriptionState> emit) async {
    final orderId = _lastOrderId;
    _lastOrderId = null;
    if (orderId != null) await _repository.abandonOrder(orderId);
    emit(PaymentProcessed(success: false, message: 'Payment Failed: ${event.response.message}'));
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    add(PaymentSuccessEvent(response));
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    add(PaymentErrorEvent(response));
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    // Handle external wallet if needed
  }

  @override
  Future<void> close() {
    _razorpay.clear();
    return super.close();
  }
}
