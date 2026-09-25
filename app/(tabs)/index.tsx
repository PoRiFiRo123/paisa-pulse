import { useLiveQuery } from 'drizzle-orm/expo-sqlite';
import { Link } from 'expo-router';
import { Text } from 'react-native';

import { appDb } from '@/db/client';
import { categoriesByKind } from '@/features/categories/queries';
import { useTheme } from '@/theme/useTheme';
import { Placeholder } from '@/ui/Placeholder';

export default function HomeScreen() {
  const { colors } = useTheme();
  const { data: expenseCategories } = useLiveQuery(categoriesByKind(appDb, 'expense'));
  return (
    <Placeholder title="Home">
      <Text style={{ color: colors.secondary }}>
        Database ready · {expenseCategories.length} expense categories
      </Text>
      <Link href="/add" style={{ color: colors.accent, fontSize: 17 }}>
        Add transaction
      </Link>
    </Placeholder>
  );
}
