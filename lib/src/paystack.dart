import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_paystack/src/common/my_strings.dart';
import 'package:flutter_paystack/src/exceptions.dart';
import 'package:flutter_paystack/src/model/checkout_response.dart';
import 'package:flutter_paystack/src/model/card.dart';
import 'package:flutter_paystack/src/model/charge.dart';
import 'package:flutter_paystack/src/platform_info.dart';
import 'package:flutter_paystack/src/transaction.dart';
import 'package:flutter_paystack/src/transaction/mobile_transaction_manager.dart';
import 'package:flutter_paystack/src/ui/widgets/checkout/checkout_widget.dart';
import 'package:flutter_paystack/src/utils/utils.dart';

class PaystackPlugin {
  static bool _sdkInitialized = false;
  static String _publicKey;
  static String _secretKey;

  PaystackPlugin._();

  /// Initialize the Paystack object. It should be called as early as possible
  /// (preferably in initState() of the Widget.
  ///
  /// [publicKey] - your paystack public key. This is mandatory
  ///
  /// [secretKey] - your paystack private key. This is not needed except you intent to
  /// use [checkout] and you want this plugin to initialize the transaction for you.
  /// Please check [checkout] for more information
  ///
  static Future<PaystackPlugin> initialize(
      {@required String publicKey, String secretKey}) async {
    assert(() {
      if (publicKey == null || publicKey.isEmpty) {
        throw new PaystackException('publicKey cannot be null or empty');
      }
      if (secretKey != null && secretKey.isEmpty) {
        throw new PaystackException(
            'privateKey can be null or but it cannot be empty. '
            'Except you are using checkout, you don\'t need to pass a privateKey');
      }
      return true;
    }());
    //do all the init work here

    var completer = Completer<PaystackPlugin>();

    //check if sdk is actually initialized
    if (sdkInitialized) {
      completer.complete(PaystackPlugin._());
    } else {
      _publicKey = publicKey;
      _secretKey = secretKey;

      // If private key is not null, it implies that checkout will be used.
      // Hence, let's get the list of supported banks. We won't wait for the result. If it
      // completes successfully, fine. If it fails, we'll retry in BankCheckout
      if (_secretKey != null) {
        Utils.getSupportedBanks();
      }

      // Using cascade notation to build the platform specific info
      try {
        String userAgent = await Utils.channel.invokeMethod('getUserAgent');
        String paystackBuild =
            await Utils.channel.invokeMethod('getVersionCode');
        String deviceId = await Utils.channel.invokeMethod('getDeviceId');
        PlatformInfo()
          ..userAgent = userAgent
          ..paystackBuild = paystackBuild
          ..deviceId = deviceId;

        _sdkInitialized = true;
        completer.complete(PaystackPlugin._());
      } on PlatformException catch (e, stacktrace) {
        completer.completeError(e, stacktrace);
      }
    }
    return completer.future;
  }

  static bool get sdkInitialized => _sdkInitialized;

  static String get publicKey {
    // Validate that the sdk has been initialized
    Utils.validateSdkInitialized();
    return _publicKey;
  }

  static String get secretKey {
    // Validate that the sdk has been initialized
    Utils.validateSdkInitialized();
    return _secretKey;
  }

  static void _performChecks({bool isSecret = false}) {
    //validate that sdk has been initialized
    Utils.validateSdkInitialized();

    if (isSecret) {
      //validate public keys
      Utils.hasPublicKey();
    } else {
      Utils.hasSecretKey();
    }
  }

  /// Make payment by chargingg the user's card
  ///
  /// [context] - the widgets BuildContext
  ///
  /// [charge] - the charge object.
  ///
  /// [beforeValidate] - Called before validation
  ///
  /// [onSuccess] - Called when the payment is completes successfully
  ///
  /// [onError] - Called when the payment completes with an unrecoverable error
  static chargeCard(BuildContext context,
      {@required Charge charge,
      @required OnTransactionChange<Transaction> beforeValidate,
      @required OnTransactionChange<Transaction> onSuccess,
      @required OnTransactionError<Object, Transaction> onError}) {
    assert(context != null, 'context must not be null');

    _performChecks();

    Paystack.withPublicKey(publicKey).chargeCard(
        context: context,
        charge: charge,
        beforeValidate: beforeValidate,
        onSuccess: onSuccess,
        onError: onError);
  }

  /// Make payment using Paystack's checkout form. The plugin will handle the whole
  /// processes involved.
  ///
  /// [context] - the widgets BuildContext
  ///
  /// [charge] - the charge object. You must pass the amount (in kobo) to it. If you
  /// want to use CheckoutMethod.card/CheckoutMethod.selectable, you must also
  /// pass either an  access code or payment reference to the charge object.
  ///
  /// Notes:
  ///
  /// * When you pass an  access code, the plugin won't
  /// initialize the transaction and payment is made immediately
  /// * When you pass the reference, the plugin will initialize the transaction
  /// (via https://api.paystack.co/transaction/initialize) with the passed reference.
  /// * You can also pass the [PaymentCard] object and we'll use it to prepopulate the
  /// card  fields if card payment is being used
  ///
  /// [onSuccess] - Called when the payment completes successfully
  ///
  /// [onValidated] - Called when the payment completes with an unrecoverable error
  ///
  /// [method] - The payment payment method to use(card, bank, USSD). It defaults to
  /// [CheckoutMethod.selectable] to allow the user to select
  static Future<CheckoutResponse> checkout(
    BuildContext context, {
    @required Charge charge,
    CheckoutMethod method = CheckoutMethod.selectable,
  }) async {
    assert(context != null, 'context must not be null');
    assert(
        method != null,
        'method must not be null. You can pass CheckoutMethod.selectable if you want the user '
        'to select the checkout option');

    _performChecks(isSecret: true);
    return Paystack.withSecretKey(secretKey)
        .checkout(context, charge: charge, method: method);
  }
}

class Paystack {
  String _publicKey;
  String _secretKey;

  Paystack() {
    // Validate sdk initialized
    Utils.validateSdkInitialized();
  }

  Paystack.withPublicKey(this._publicKey);

  Paystack.withSecretKey(this._secretKey);

  chargeCard(
      {@required BuildContext context,
      @required Charge charge,
      @required OnTransactionChange<Transaction> beforeValidate,
      @required OnTransactionChange<Transaction> onSuccess,
      @required OnTransactionError<Object, Transaction> onError}) {
    try {
      //check for null value, and length and starts with pk_
      if (_publicKey == null ||
          _publicKey.isEmpty ||
          !_publicKey.startsWith("pk_")) {
        throw new AuthenticationException(Utils.getKeyErrorMsg('public'));
      }

      new MobileTransactionManager(
              charge: charge,
              context: context,
              beforeValidate: beforeValidate,
              onSuccess: onSuccess,
              onError: onError)
          .chargeCard();
    } catch (e) {
      if (e is AuthenticationException) {
        rethrow;
      }
      assert(onError != null);
      onError(e, null);
    }
  }

  Future<CheckoutResponse> checkout(
    BuildContext context, {
    @required Charge charge,
    @required CheckoutMethod method,
  }) async {
    assert(() {
      Utils.validateChargeAndKeys(charge);

      if ((method == CheckoutMethod.selectable ||
              method == CheckoutMethod.card) &&
          (charge.accessCode == null && charge.reference == null)) {
        throw new ChargeException(Strings.noAccessCodeReference);
      }
      return true;
    }());

    CheckoutResponse response = await showDialog(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) =>
            new CheckoutWidget(method: method, charge: charge));
    return response == null ? CheckoutResponse.defaults() : response;
  }
}

typedef void OnTransactionChange<Transaction>(Transaction transaction);
typedef void OnTransactionError<Object, Transaction>(
    Object e, Transaction transaction);

enum CheckoutMethod { card, bank, selectable }
