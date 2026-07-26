import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import '../models/nfc_customer_lookup.dart';

class NfcReaderService {
  const NfcReaderService();

  Future<bool> get isSupported async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    final availability = await NfcManager.instance.checkAvailability();
    return availability == NfcAvailability.enabled;
  }

  Future<String?> readTagUid({Duration timeout = const Duration(seconds: 30)}) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value(null);
    }

    final completer = Completer<String?>();
    var finished = false;

    void complete(String? value) {
      if (finished) return;
      finished = true;
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    NfcManager.instance.startSession(
      pollingOptions: const {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      onDiscovered: (tag) async {
        try {
          final uid = uidFromTag(tag);
          await NfcManager.instance.stopSession();
          complete(uid);
        } catch (_) {
          await NfcManager.instance.stopSession();
          complete(null);
        }
      },
    ).catchError((_) {
      complete(null);
    });

    Future<void>.delayed(timeout, () async {
      if (finished) return;
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
      complete(null);
    });

    return completer.future;
  }

  Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  static String? uidFromTag(NfcTag tag) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null && androidTag.id.isNotEmpty) {
        return normalizeNfcUid(
          androidTag.id
              .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
              .join(),
        );
      }
    }

    return null;
  }
}
