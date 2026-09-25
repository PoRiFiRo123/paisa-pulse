import { format } from 'date-fns';
import { LinearGradient } from 'expo-linear-gradient';
import { Pressable, StyleSheet, Text, View } from 'react-native';

import type { Account } from '@/db/schema';
import { useMoney } from '@/hooks/useMoney';
import { type } from '@/theme/typography';

import { Icon } from '@/ui/Icon';

import { ACCOUNT_TYPE_LABEL, accountIcon, daysUntilDay } from './presentation';

export const CARD_HEIGHT = 200;
/** Visible strip of each stacked card (Figma: cards 64pt apart). */
export const CARD_PEEK = 64;

function shade(hex: string, amount: number): string {
  const n = parseInt(hex.slice(1), 16);
  const f = (c: number) => Math.max(0, Math.min(255, Math.round(c + (amount < 0 ? c : 255 - c) * amount)));
  return `#${[(n >> 16) & 255, (n >> 8) & 255, n & 255].map((c) => f(c).toString(16).padStart(2, '0')).join('')}`;
}

/** Wallet-style account card: solid content (not glass), balance on each. */
export function AccountCard({
  account,
  balance,
  onPress,
  showHeaderBalance = true,
}: {
  account: Account;
  balance: number;
  onPress?: () => void;
  showHeaderBalance?: boolean;
}) {
  const money = useMoney();
  const subtitle = `${ACCOUNT_TYPE_LABEL[account.type]}${account.last4 ? ` ••${account.last4}` : ''}`;
  let footnote = account.type === 'cash' ? 'Cash in hand' : 'Available balance';
  if (account.type === 'card') {
    const due = account.dueDay ? `Due ${format(daysUntilDay(account.dueDay).date, 'd MMM')}` : 'Outstanding';
    footnote = account.creditLimit ? `${due} · limit ${money.amount(account.creditLimit)}` : due;
  }
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`${account.name}, ${subtitle}, balance ${money.balance(balance)}`}
      style={({ pressed }) => [styles.shadow, { transform: [{ scale: pressed ? 0.98 : 1 }] }]}
    >
      <LinearGradient colors={[shade(account.color, 0.12), shade(account.color, -0.25)]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.card}>
        <View style={styles.head}>
          <View style={{ flex: 1 }}>
            <Text style={[type.headline, styles.white]} numberOfLines={1}>
              {account.name}
            </Text>
            <Text style={[type.footnote, styles.dim]}>{subtitle}</Text>
          </View>
          {showHeaderBalance ? <Text style={[type.bodyAmount, styles.white]}>{money.balance(balance)}</Text> : null}
        </View>
        <View style={styles.chip}>
          <Icon name={accountIcon(account.type)} size={22} color="rgba(255,255,255,0.85)" />
        </View>
        <View>
          <Text style={[type.amountMedium, styles.white, { fontSize: 28 }]} adjustsFontSizeToFit numberOfLines={1}>
            {money.balance(balance)}
          </Text>
          <Text style={[type.footnote, styles.dim]}>{footnote}</Text>
        </View>
      </LinearGradient>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  shadow: {
    borderRadius: 22,
    shadowColor: '#000',
    shadowOpacity: 0.18,
    shadowRadius: 14,
    shadowOffset: { width: 0, height: -2 },
    elevation: 6,
  },
  card: { height: CARD_HEIGHT, borderRadius: 22, padding: 20, paddingTop: 18, justifyContent: 'space-between' },
  head: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  chip: { position: 'absolute', right: 20, bottom: 20 },
  white: { color: '#FFFFFF' },
  dim: { color: 'rgba(255,255,255,0.75)', marginTop: 2 },
});
