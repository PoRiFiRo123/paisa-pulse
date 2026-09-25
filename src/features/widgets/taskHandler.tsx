import type { WidgetTaskHandler } from 'react-native-android-widget';

import { renderSpendingWidget } from './SpendingWidget';
import { readSnapshotFile } from './store';

/** Runs headless when Android asks for a widget update (added, resized, periodic). */
export const widgetTaskHandler: WidgetTaskHandler = async ({ widgetInfo, widgetAction, renderWidget }) => {
  if (widgetAction === 'WIDGET_DELETED') return;
  const snapshot = await readSnapshotFile();
  renderWidget(renderSpendingWidget(snapshot, widgetInfo.width));
};
