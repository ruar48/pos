import 'package:flutter/material.dart';

import '../../../core/theme/agri_admin_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../pos/pages/pos_home_page.dart';
import 'inventory_management_widgets.dart';
import 'products_management_widgets.dart';

enum CatalogTab { inventory, products }

class CatalogManagementContent extends StatefulWidget {
  const CatalogManagementContent({
    super.key,
    required this.pageState,
    this.initialTab = CatalogTab.inventory,
  });

  final PosHomePageState pageState;
  final CatalogTab initialTab;

  @override
  State<CatalogManagementContent> createState() =>
      _CatalogManagementContentState();
}

class _CatalogManagementContentState extends State<CatalogManagementContent>
    with SingleTickerProviderStateMixin {
  late final TabController tabController;

  @override
  void initState() {
    super.initState();
    tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.pageState.refreshProductCatalog();
    });
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: AgriCard(
            padding: const EdgeInsets.all(4),
            child: TabBar(
              controller: tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              labelColor: AppColors.green,
              unselectedLabelColor: AppColors.muted,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
              tabs: const [
                Tab(
                  height: 48,
                  icon: Icon(Icons.warehouse_outlined, size: 20),
                  text: 'Inventory',
                ),
                Tab(
                  height: 48,
                  icon: Icon(Icons.inventory_2_outlined, size: 20),
                  text: 'Products',
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: tabController,
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: InventoryManagementContent(
                  pageState: widget.pageState,
                  onRefresh: _refresh,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: ProductsManagementContent(
                  pageState: widget.pageState,
                  onRefresh: _refresh,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
