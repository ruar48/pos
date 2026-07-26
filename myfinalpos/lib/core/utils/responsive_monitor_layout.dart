enum MonitorLayoutDensity { phone, tablet, desktop, tv, ultra }

class MonitorLayoutMetrics {
  const MonitorLayoutMetrics({
    required this.density,
    required this.crossAxisCount,
    required this.childAspectRatio,
    required this.gridSpacing,
    required this.titleSize,
    required this.totalSize,
    required this.chipSize,
    required this.headerPadding,
    required this.cardPadding,
  });

  final MonitorLayoutDensity density;
  final int crossAxisCount;
  final double childAspectRatio;
  final double gridSpacing;
  final double titleSize;
  final double totalSize;
  final double chipSize;
  final double headerPadding;
  final double cardPadding;

  static MonitorLayoutMetrics forWidth(double width) {
    if (width >= 2560) {
      return const MonitorLayoutMetrics(
        density: MonitorLayoutDensity.ultra,
        crossAxisCount: 5,
        childAspectRatio: 1.02,
        gridSpacing: 18,
        titleSize: 28,
        totalSize: 34,
        chipSize: 14,
        headerPadding: 22,
        cardPadding: 18,
      );
    }
    if (width >= 1920) {
      return const MonitorLayoutMetrics(
        density: MonitorLayoutDensity.tv,
        crossAxisCount: 4,
        childAspectRatio: 0.98,
        gridSpacing: 16,
        titleSize: 24,
        totalSize: 30,
        chipSize: 13,
        headerPadding: 20,
        cardPadding: 16,
      );
    }
    if (width >= 1200) {
      return const MonitorLayoutMetrics(
        density: MonitorLayoutDensity.desktop,
        crossAxisCount: 3,
        childAspectRatio: 0.92,
        gridSpacing: 14,
        titleSize: 18,
        totalSize: 22,
        chipSize: 12,
        headerPadding: 16,
        cardPadding: 14,
      );
    }
    if (width >= 720) {
      return const MonitorLayoutMetrics(
        density: MonitorLayoutDensity.tablet,
        crossAxisCount: 2,
        childAspectRatio: 0.88,
        gridSpacing: 12,
        titleSize: 17,
        totalSize: 20,
        chipSize: 12,
        headerPadding: 14,
        cardPadding: 12,
      );
    }
    return const MonitorLayoutMetrics(
      density: MonitorLayoutDensity.phone,
      crossAxisCount: 1,
      childAspectRatio: 0.78,
      gridSpacing: 10,
      titleSize: 16,
      totalSize: 22,
      chipSize: 11,
      headerPadding: 12,
      cardPadding: 12,
    );
  }
}
