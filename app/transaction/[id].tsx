import { useLocalSearchParams } from 'expo-router';

import { Placeholder } from '@/ui/Placeholder';

export default function TransactionDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  return <Placeholder title={`Transaction ${id}`} />;
}
