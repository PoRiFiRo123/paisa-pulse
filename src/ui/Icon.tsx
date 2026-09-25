import { type AndroidSymbol, SymbolView, type SymbolWeight } from 'expo-symbols';
import type { ColorValue } from 'react-native';
import type { SFSymbol } from 'sf-symbols-typescript';

/** SF Symbol → Material Symbol, so one icon name works on both platforms. */
const ANDROID: Record<string, AndroidSymbol> = {
  // UI
  magnifyingglass: 'search',
  plus: 'add',
  'plus.circle.fill': 'add_circle',
  calendar: 'calendar_month',
  ellipsis: 'more_horiz',
  'ellipsis.circle.fill': 'more_horiz',
  'chevron.down': 'expand_more',
  'chevron.right': 'chevron_right',
  'chevron.left': 'chevron_left',
  'chevron.up.chevron.down': 'unfold_more',
  'arrow.down.right': 'south_east',
  'arrow.up.right': 'north_east',
  'arrow.down.left': 'south_west',
  'arrow.up': 'arrow_upward',
  'arrow.down': 'arrow_downward',
  'arrow.left.arrow.right': 'swap_horiz',
  'arrow.up.arrow.down': 'swap_vert',
  checkmark: 'check',
  'checkmark.seal.fill': 'verified',
  xmark: 'close',
  trash: 'delete',
  'doc.on.doc': 'content_copy',
  'square.and.arrow.up': 'ios_share',
  'square.and.arrow.down': 'download',
  'line.3.horizontal.decrease': 'filter_list',
  'delete.left': 'backspace',
  'lock.fill': 'lock',
  'faceid': 'face',
  tag: 'sell',
  'tag.fill': 'sell',
  'moon.fill': 'dark_mode',
  pencil: 'edit',
  clock: 'schedule',
  'note.text': 'notes',
  'bell.fill': 'notifications',
  'paintpalette.fill': 'palette',
  'eye.slash.fill': 'visibility_off',
  'calendar.badge.clock': 'event_repeat',
  'list.bullet': 'list',
  'list.bullet.rectangle.portrait': 'receipt_long',
  house: 'home',
  'house.fill': 'home',
  creditcard: 'credit_card',
  'creditcard.fill': 'credit_card',
  gearshape: 'settings',
  'gearshape.fill': 'settings',
  'indianrupeesign': 'currency_rupee',
  'indianrupeesign.circle.fill': 'currency_rupee',
  'wallet.bifold.fill': 'account_balance_wallet',
  'banknote.fill': 'payments',
  'building.columns.fill': 'account_balance',
  'questionmark': 'question_mark',
  'archivebox': 'archive',
  'arrow.triangle.merge': 'merge',
  'textformat': 'text_fields',
  'shield.lefthalf.filled': 'shield',
  'square.grid.2x2': 'grid_view',
  'chart.pie.fill': 'pie_chart',
  'chart.bar.fill': 'bar_chart',
  'arrow.clockwise': 'refresh',
  'repeat': 'repeat',
  'pause.circle': 'pause_circle',
  'play.circle': 'play_circle',
  'bookmark': 'bookmark',
  'bookmark.fill': 'bookmark',
  'app.badge': 'apps',
  'checkmark.circle': 'check_circle',
  'checkmark.circle.fill': 'check_circle',
  circle: 'radio_button_unchecked',
  'checklist': 'checklist',
  'line.3.horizontal': 'drag_handle',
  number: 'dialpad',
  'person.crop.circle': 'account_circle',
  'info.circle': 'info',
  'hand.raised.fill': 'back_hand',
  'iphone': 'smartphone',
  // Categories
  'fork.knife': 'restaurant',
  'cart.fill': 'shopping_cart',
  'car.fill': 'directions_car',
  'fuelpump.fill': 'local_gas_station',
  'tram.fill': 'tram',
  'bag.fill': 'shopping_bag',
  'doc.text.fill': 'receipt',
  'bolt.fill': 'bolt',
  wifi: 'wifi',
  'tv.fill': 'tv',
  'cross.case.fill': 'medical_services',
  'popcorn.fill': 'movie',
  'repeat.circle.fill': 'autorenew',
  airplane: 'flight',
  'graduationcap.fill': 'school',
  'gift.fill': 'redeem',
  'chart.line.uptrend.xyaxis': 'trending_up',
  sparkles: 'auto_awesome',
  'figure.2.and.child.holdinghands': 'family_restroom',
  laptopcomputer: 'laptop',
  percent: 'percent',
  'arrow.uturn.backward.circle.fill': 'undo',
  'cup.and.saucer.fill': 'local_cafe',
  'pawprint.fill': 'pets',
  'dumbbell.fill': 'fitness_center',
  'gamecontroller.fill': 'sports_esports',
  'book.fill': 'menu_book',
  'music.note': 'music_note',
  'phone.fill': 'call',
  'drop.fill': 'water_drop',
  'flame.fill': 'local_fire_department',
  'wrench.and.screwdriver.fill': 'build',
  'tshirt.fill': 'checkroom',
  'scissors': 'content_cut',
  'pills.fill': 'medication',
  'bus.fill': 'directions_bus',
  'bicycle': 'pedal_bike',
  'heart.fill': 'favorite',
  'star.fill': 'star',
  'briefcase.fill': 'work',
  'globe': 'public',
  'leaf.fill': 'eco',
  'film.fill': 'movie',
  'play.rectangle.fill': 'smart_display',
};

export type IconProps = {
  name: string;
  size?: number;
  color?: ColorValue;
  weight?: SymbolWeight;
};

/** SF Symbol on iOS, Material Symbol on Android. */
export function Icon({ name, size = 20, color, weight = 'medium' }: IconProps) {
  return (
    <SymbolView
      name={{ ios: name as SFSymbol, android: ANDROID[name] ?? 'circle', web: ANDROID[name] ?? 'circle' }}
      size={size}
      tintColor={color}
      weight={weight}
      resizeMode="scaleAspectFit"
      style={{ width: size, height: size }}
    />
  );
}

export const ANDROID_SYMBOLS = ANDROID;
