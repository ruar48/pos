const double posSplitBreakpoint = 720;
const double posMaxCartWidth = 430;
const double posMinCartWidth = 300;

double cartPanelWidth(double screenWidth) {
  if (screenWidth < posSplitBreakpoint) return screenWidth;
  return (screenWidth * 0.38).clamp(posMinCartWidth, posMaxCartWidth);
}
