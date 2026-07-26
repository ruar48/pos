import 'package:flutter/material.dart';

import '../../management/widgets/management_widgets.dart';
import '../widgets/app_drawer_section.dart';
import '../widgets/tablet_printer_settings_panel.dart';
import 'pos_home_page.dart';

class TabletPrinterPage extends StatelessWidget {
  const TabletPrinterPage({super.key, required this.pageState});

  final PosHomePageState pageState;

  @override
  Widget build(BuildContext context) {
    return ManagementPageShell(
      pageState: pageState,
      activeSection: AppDrawerSection.tabletPrinter,
      title: 'My Printer',
      subtitle:
          'This tablet only. Each cashier can connect their own Bluetooth, USB, or network printer here.',
      child: TabletPrinterSettingsPanel(pageState: pageState),
    );
  }
}
