import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:myfinalpos/features/receipt/printer_transport.dart';
import 'package:myfinalpos/features/receipt/receipt_print_exception.dart';
import 'package:myfinalpos/models/printer_settings.dart';

void main() {
  test('print jobs run one at a time, in the order they were queued',
      () async {
    final events = <String>[];
    final firstGate = Completer<void>();

    final first = PrinterTransport.runExclusive(() async {
      events.add('first start');
      await firstGate.future;
      events.add('first end');
    });
    final second = PrinterTransport.runExclusive(() async {
      events.add('second start');
    });

    await pumpEventQueue();
    expect(events, ['first start']);
    expect(PrinterTransport.busy.value, isTrue);

    firstGate.complete();
    await Future.wait([first, second]);
    expect(events, ['first start', 'first end', 'second start']);

    await pumpEventQueue();
    expect(PrinterTransport.busy.value, isFalse);
  });

  test('a failed job still reports its error and does not block the next',
      () async {
    final failed = PrinterTransport.runExclusive<void>(
      () async => throw ReceiptPrintException('Paper jam'),
    );
    final next = PrinterTransport.runExclusive(() async => 'printed');

    await expectLater(failed, throwsA(isA<ReceiptPrintException>()));
    expect(await next, 'printed');
  });

  test('overlapping network prints reach the printer one after another',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final clients = <Socket>[];
    addTearDown(() async {
      for (final client in clients) {
        client.destroy();
      }
      await server.close();
    });

    final clock = Stopwatch()..start();
    final acceptedAtMs = <int>[];
    final received = <List<int>>[];
    var finished = 0;
    final bothFinished = Completer<void>();
    server.listen((client) {
      // The fake printer never closes its side, like most real ones - the
      // sender must still complete on its own.
      clients.add(client);
      acceptedAtMs.add(clock.elapsedMilliseconds);
      final data = <int>[];
      received.add(data);
      client.listen(data.addAll, onDone: () {
        if (++finished == 2) bothFinished.complete();
      });
    });

    final config = PrinterConfig(host: '127.0.0.1', port: server.port);
    // 1024 bytes = four 256-byte chunks with a 20 ms pause between each, so
    // the first job holds its connection for at least ~60 ms.
    final firstJob = List<int>.filled(1024, 0x41);
    final secondJob = List<int>.filled(1024, 0x42);

    await Future.wait([
      PrinterTransport.sendEscPos(config: config, bytes: firstJob),
      PrinterTransport.sendEscPos(config: config, bytes: secondJob),
    ]).timeout(const Duration(seconds: 20));
    await bothFinished.future.timeout(const Duration(seconds: 5));

    expect(received, [firstJob, secondJob]);
    // Run together, both connections open within a few ms of each other;
    // queued, the second can't connect until the first has finished.
    expect(acceptedAtMs[1] - acceptedAtMs[0], greaterThanOrEqualTo(40));
  });
}
