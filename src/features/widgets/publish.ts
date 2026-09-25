import { Platform } from 'react-native';

import { HAS_CUSTOM_NATIVE } from '@/lib/native';

import type { WidgetSnapshot } from './snapshot';
import { writeSnapshotFile } from './store';

/** Shared with the iOS widget extension (see targets/widget and ios.entitlements in app.json). */
export const APP_GROUP = 'group.com.paisapulse.app';
export const ANDROID_WIDGET = 'Spending';

/**
 * Push the latest numbers to home/lock screen widgets. Widget modules are required lazily:
 * they don't exist in Expo Go and would throw at import there.
 */
export async function publishWidgets(snapshot: WidgetSnapshot): Promise<void> {
  if (!HAS_CUSTOM_NATIVE) return;
  if (Platform.OS === 'ios') {
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- lazy: absent in Expo Go
    const { ExtensionStorage } = require('@bacons/apple-targets') as typeof import('@bacons/apple-targets');
    new ExtensionStorage(APP_GROUP).set('snapshot', JSON.stringify(snapshot));
    ExtensionStorage.reloadWidget();
  } else if (Platform.OS === 'android') {
    writeSnapshotFile(snapshot);
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- lazy: absent in Expo Go
    const { requestWidgetUpdate } = require('react-native-android-widget') as typeof import('react-native-android-widget');
    // eslint-disable-next-line @typescript-eslint/no-require-imports -- imports the widget library
    const { renderSpendingWidget } = require('./SpendingWidget') as typeof import('./SpendingWidget');
    await requestWidgetUpdate({
      widgetName: ANDROID_WIDGET,
      renderWidget: (info) => renderSpendingWidget(snapshot, info.width),
      widgetNotFound: () => {},
    }).catch(() => {});
  }
}
