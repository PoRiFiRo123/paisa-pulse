// App entry: Expo Router, plus the Android home screen widget task handler.
import 'expo-router/entry';

import Constants, { ExecutionEnvironment } from 'expo-constants';
import { Platform } from 'react-native';

// The widget module only exists in development/store builds, not in Expo Go.
if (Platform.OS === 'android' && Constants.executionEnvironment !== ExecutionEnvironment.StoreClient) {
  const { registerWidgetTaskHandler } = require('react-native-android-widget');
  const { widgetTaskHandler } = require('./src/features/widgets/taskHandler');
  registerWidgetTaskHandler(widgetTaskHandler);
}
