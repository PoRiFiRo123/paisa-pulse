import { type ColorProp, FlexWidget, TextWidget } from 'react-native-android-widget';

import type { WidgetSnapshot } from './snapshot';

type Palette = Record<'bg' | 'label' | 'secondary' | 'track' | 'accent' | 'over', ColorProp>;
const LIGHT: Palette = { bg: '#FFFFFF', label: '#000000', secondary: '#8A8A8E', track: '#E9E9EE', accent: '#5E5CE6', over: '#FF3B30' };
const DARK: Palette = { bg: '#1C1C1E', label: '#FFFFFF', secondary: '#8E8E93', track: '#2C2C2E', accent: '#7D7AFF', over: '#FF453A' };

/** Android home screen widget: month spend, budget bar, today, and an Add button. */
function Widget({ s, p, wide }: { s: WidgetSnapshot | null; p: Palette; wide: boolean }) {
  if (!s) {
    return (
      <FlexWidget style={{ height: 'match_parent', width: 'match_parent', backgroundColor: p.bg, borderRadius: 22, padding: 16, justifyContent: 'center' }} clickAction="OPEN_APP">
        <TextWidget text="Open Paisa Pulse to set up" style={{ fontSize: 14, color: p.secondary }} />
      </FlexWidget>
    );
  }
  const ratio = s.budget?.ratio ?? 0;
  return (
    <FlexWidget
      style={{ height: 'match_parent', width: 'match_parent', backgroundColor: p.bg, borderRadius: 22, padding: 16, flexDirection: 'column', justifyContent: 'space-between' }}
      clickAction="OPEN_URI"
      clickActionData={{ uri: 'paisapulse://' }}
    >
      <FlexWidget style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', width: 'match_parent' }}>
        <TextWidget text={`Spent in ${s.month}`} style={{ fontSize: 13, color: p.secondary }} />
        <FlexWidget
          style={{ backgroundColor: p.accent, borderRadius: 16, paddingHorizontal: 12, paddingVertical: 4 }}
          clickAction="OPEN_URI"
          clickActionData={{ uri: 'paisapulse://add?type=expense' }}
        >
          <TextWidget text="+ Add" style={{ fontSize: 13, color: '#FFFFFF', fontWeight: '600' }} />
        </FlexWidget>
      </FlexWidget>
      <TextWidget text={s.spent} style={{ fontSize: wide ? 34 : 28, color: p.label, fontWeight: '700' }} />
      {s.budget ? (
        <FlexWidget style={{ flexDirection: 'column', width: 'match_parent' }}>
          <FlexWidget style={{ height: 6, width: 'match_parent', backgroundColor: p.track, borderRadius: 3, flexDirection: 'row' }}>
            <FlexWidget style={{ height: 6, flex: Math.max(ratio, 0.02), backgroundColor: s.budget.over ? p.over : p.accent, borderRadius: 3 }} />
            <FlexWidget style={{ height: 6, flex: Math.max(1 - ratio, 0.001) }} />
          </FlexWidget>
          <TextWidget text={s.budget.label} style={{ fontSize: 12, color: s.budget.over ? p.over : p.secondary, marginTop: 4 }} />
        </FlexWidget>
      ) : null}
      <TextWidget text={`Today ${s.today}`} style={{ fontSize: 13, color: p.secondary }} />
      {wide
        ? s.top.map((t) => (
            <FlexWidget key={t.name} style={{ flexDirection: 'row', justifyContent: 'space-between', width: 'match_parent' }}>
              <TextWidget text={`● ${t.name}`} style={{ fontSize: 13, color: p.label }} />
              <TextWidget text={t.amount} style={{ fontSize: 13, color: p.label, fontWeight: '600' }} />
            </FlexWidget>
          ))
        : null}
    </FlexWidget>
  );
}

export function renderSpendingWidget(snapshot: WidgetSnapshot | null, widthDp = 180) {
  const wide = widthDp >= 250;
  return { light: <Widget s={snapshot} p={LIGHT} wide={wide} />, dark: <Widget s={snapshot} p={DARK} wide={wide} /> };
}
