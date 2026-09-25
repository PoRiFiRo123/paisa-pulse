import { format } from 'date-fns';
import * as DocumentPicker from 'expo-document-picker';
import { File } from 'expo-file-system';
import * as Haptics from 'expo-haptics';
import { router, useLocalSearchParams } from 'expo-router';
import { useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { appDb } from '@/db/client';
import { type TransactionType } from '@/db/schema';
import { accountIcon } from '@/features/accounts/presentation';
import { accountsWithBalance } from '@/features/accounts/queries';
import { categoriesByKind } from '@/features/categories/queries';
import { guessAccount } from '@/features/import/guessAccount';
import { loadStatement } from '@/features/import/loadStatement';
import {
  balanceMismatches,
  COLUMN_ROLE_LABEL,
  type ColumnRole,
  detectMapping,
  detectTemplate,
  extractRows,
  type Mapping,
  type StatementTemplate,
} from '@/features/import/parse';
import { usePdfExtractor } from '@/features/import/PdfExtractor';
import { commitImport, listImportBatches, type PlannedRow, planImport, restoreImport, undoImport } from '@/features/import/plan';
import type { Sheet } from '@/features/import/readers/csv';
import { useMoney } from '@/hooks/useMoney';
import { useQuery } from '@/hooks/useQuery';
import { accountLabel } from '@/lib/format';
import { useToast } from '@/stores/toast';
import { TRANSFER_COLOR, UNCATEGORISED_COLOR } from '@/theme/tokens';
import { type } from '@/theme/typography';
import { useTheme } from '@/theme/useTheme';
import { CategoryIcon } from '@/ui/CategoryIcon';
import { EmptyState } from '@/ui/EmptyState';
import { GlassButton, GlassSurface } from '@/ui/Glass';
import { Icon } from '@/ui/Icon';
import { GroupHeader, GroupRow, InsetGroup } from '@/ui/InsetGroup';
import { Menu, type MenuItem } from '@/ui/Menu';
import { NamePrompt } from '@/ui/NamePrompt';
import { LargeTitle, TopBar, useScrollHeader, useTitleTop } from '@/ui/Screen';

type Step =
  | { kind: 'pick' }
  | { kind: 'password'; bytes: Uint8Array; fileName: string; retry: boolean }
  | { kind: 'setup'; sheet: Sheet; fileName: string; template: StatementTemplate | null }
  | {
      kind: 'review';
      fileName: string;
      template: StatementTemplate | null;
      rows: PlannedRow[];
      mismatches: number | null;
      /** The setup step to return to. */
      setup: { kind: 'setup'; sheet: Sheet; fileName: string; template: StatementTemplate | null };
    };

const ROLES: ColumnRole[] = ['date', 'description', 'debit', 'credit', 'amount', 'drcr', 'balance', 'reference', 'valueDate', 'ignore'];

export default function ImportScreen() {
  const params = useLocalSearchParams<{ accountId?: string }>();
  const { colors } = useTheme();
  const toast = useToast((s) => s.show);
  const extractPdf = usePdfExtractor();
  const { scrollY, onScroll } = useScrollHeader();
  const top = useTitleTop();
  const insets = useSafeAreaInsets();
  const [step, setStep] = useState<Step>({ kind: 'pick' });
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [accountId, setAccountId] = useState<string | undefined>(params.accountId);
  const [mapping, setMapping] = useState<Mapping | null>(null);
  const { data: accounts } = useQuery(() => accountsWithBalance(appDb), [], []);
  const { data: batches } = useQuery(() => listImportBatches(appDb), [], []);
  const account = accounts.find((a) => a.id === accountId);

  const read = async (bytes: Uint8Array, fileName: string, password?: string) => {
    setBusy(password ? 'Unlocking…' : 'Reading statement…');
    setError(null);
    try {
      const result = await loadStatement(bytes, extractPdf, password);
      if (!result.ok) {
        if (result.error === 'password' || result.error === 'incorrect-password') {
          setStep({ kind: 'password', bytes, fileName, retry: result.error === 'incorrect-password' });
        } else setError(result.error);
        return;
      }
      const template = detectTemplate(result.sheet);
      const guessed = params.accountId ? accounts.find((a) => a.id === params.accountId) : guessAccount(accounts, template);
      setAccountId(guessed?.id);
      const detected = detectMapping(result.sheet, template, guessed?.type === 'card' ? 'card' : 'bank');
      if (!detected) {
        setError('Couldn’t find the transactions table in this file. Try the CSV or Excel download from your bank.');
        return;
      }
      setMapping(detected);
      setStep({ kind: 'setup', sheet: result.sheet, fileName, template });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };

  const pick = async () => {
    const res = await DocumentPicker.getDocumentAsync({
      type: ['application/pdf', 'text/csv', 'text/comma-separated-values', 'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', 'text/html', '*/*'],
      copyToCacheDirectory: true,
    });
    if (res.canceled || !res.assets?.[0]) return;
    const asset = res.assets[0];
    // On web the picker returns a browser File; native returns a file:// URI.
    const bytes = asset.file ? new Uint8Array(await asset.file.arrayBuffer()) : await new File(asset.uri).bytes();
    await read(bytes, asset.name);
  };

  const rowsPreview = useMemo(() => {
    if (step.kind !== 'setup' || !mapping) return [];
    return extractRows(step.sheet, mapping);
  }, [step, mapping]);

  const review = async () => {
    if (step.kind !== 'setup' || !mapping || !accountId) return;
    setBusy('Checking for duplicates…');
    try {
      const rows = await planImport(appDb, accountId, rowsPreview);
      setStep({ kind: 'review', fileName: step.fileName, template: step.template, rows, mismatches: balanceMismatches(rowsPreview), setup: step });
    } finally {
      setBusy(null);
    }
  };

  const commit = async () => {
    if (step.kind !== 'review' || !accountId) return;
    setBusy('Importing…');
    try {
      const { batchId, count } = await commitImport(appDb, { accountId, fileName: step.fileName, template: step.template?.id ?? null, rows: step.rows });
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      toast({ message: `Imported ${count} transaction${count === 1 ? '' : 's'}`, actionLabel: 'Undo', onAction: () => undoImport(appDb, batchId) });
      router.back();
    } finally {
      setBusy(null);
    }
  };

  const title = step.kind === 'review' ? 'Review' : 'Import Statement';
  const back = () => {
    if (step.kind === 'review') setStep(step.setup);
    else if (step.kind === 'setup') setStep({ kind: 'pick' });
    else router.back();
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.background }}>
      {step.kind === 'review' ? (
        <ReviewList
          rows={step.rows}
          accountId={accountId!}
          onChange={(rows) => setStep({ ...step, rows })}
          header={
            <View style={{ paddingTop: top }}>
              <LargeTitle title="Review" />
              <ReviewSummary rows={step.rows} mismatches={step.mismatches} fileName={step.fileName} accountName={account?.name} />
            </View>
          }
          onScroll={onScroll}
          bottom={insets.bottom + 110}
        />
      ) : (
        <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingTop: top, paddingBottom: 80 }}>
          <LargeTitle title="Import Statement" />
          {error ? (
            <View style={[styles.error, { backgroundColor: `${colors.expense}1A` }]}>
              <Icon name="exclamationmark.triangle.fill" size={16} color={colors.expense} />
              <Text style={[type.subhead, { color: colors.label, flex: 1 }]}>{error}</Text>
            </View>
          ) : null}

          {step.kind === 'pick' || step.kind === 'password' ? (
            <>
              <View style={[styles.card, { backgroundColor: colors.card }]}>
                <Text style={[type.headline, { color: colors.label }]}>Bring in months of history in one go</Text>
                <Text style={[type.subhead, { color: colors.secondary }]}>
                  Download a statement from your bank’s app or net banking (PDF, CSV or Excel) and pick it here. It’s read on this phone
                  only — nothing is uploaded.
                </Text>
                <Text style={[type.footnote, { color: colors.secondary }]}>
                  Recognised: Axis Bank, Bank of Baroda, HDFC Bank, ICICI Bank, SBI and their credit cards. Other banks work too — you
                  can match the columns yourself.
                </Text>
                <Pressable onPress={pick} disabled={!!busy} accessibilityRole="button" style={{ marginTop: 8 }}>
                  <GlassSurface radius={24} tint={colors.accent} interactive style={styles.cta}>
                    <Icon name="square.and.arrow.down" size={18} color="#FFFFFF" weight="semibold" />
                    <Text style={[type.headline, { color: '#FFFFFF' }]}>Choose Statement File</Text>
                  </GlassSurface>
                </Pressable>
              </View>
              <RecentImports batches={batches} onUndo={(id) => undoImport(appDb, id)} onRestore={(id) => restoreImport(appDb, id)} />
            </>
          ) : null}

          {step.kind === 'setup' && mapping ? (
            <SetupStep
              sheet={step.sheet}
              template={step.template}
              fileName={step.fileName}
              mapping={mapping}
              onMapping={setMapping}
              accountId={accountId}
              onAccount={(id) => {
                setAccountId(id);
                // A single Amount column reads differently on card and bank statements.
                const kind = accounts.find((a) => a.id === id)?.type === 'card' ? 'out' : 'in';
                if (!step.template) setMapping({ ...mapping, positiveIs: kind });
              }}
              accounts={accounts}
              previewCount={rowsPreview.length}
              onContinue={review}
              busy={!!busy}
            />
          ) : null}
        </ScrollView>
      )}

      {busy ? (
        <View style={[StyleSheet.absoluteFill, styles.busy]}>
          <GlassSurface radius={20} style={styles.busyCard}>
            <ActivityIndicator color={colors.accent} />
            <Text style={[type.subhead, { color: colors.label }]}>{busy}</Text>
          </GlassSurface>
        </View>
      ) : null}

      {step.kind === 'review' ? (
        <View style={[styles.commitBar, { bottom: insets.bottom + 16 }]}>
          <Pressable onPress={commit} accessibilityRole="button" disabled={!step.rows.some((r) => r.include)}>
            <GlassSurface radius={28} tint={colors.accent} interactive style={[styles.commit, { opacity: step.rows.some((r) => r.include) ? 1 : 0.5 }]}>
              <Text style={[type.headline, { color: '#FFFFFF' }]}>
                Import {step.rows.filter((r) => r.include).length} to {account?.name ?? 'account'}
              </Text>
            </GlassSurface>
          </Pressable>
        </View>
      ) : null}

      <TopBar title={title} scrollY={scrollY} leading={<GlassButton icon="chevron.left" accessibilityLabel="Back" onPress={back} />} />

      <NamePrompt
        visible={step.kind === 'password'}
        title={step.kind === 'password' && step.retry ? 'Wrong password — try again' : 'This PDF is password-protected'}
        placeholder="Statement password"
        confirmLabel="Unlock"
        secure
        onCancel={() => setStep({ kind: 'pick' })}
        onConfirm={(pw) => step.kind === 'password' && read(step.bytes, step.fileName, pw)}
      />
    </View>
  );
}

function SetupStep({
  sheet,
  template,
  fileName,
  mapping,
  onMapping,
  accountId,
  onAccount,
  accounts,
  previewCount,
  onContinue,
  busy,
}: {
  sheet: Sheet;
  template: StatementTemplate | null;
  fileName: string;
  mapping: Mapping;
  onMapping: (m: Mapping) => void;
  accountId?: string;
  onAccount: (id: string) => void;
  accounts: Awaited<ReturnType<typeof accountsWithBalance>>;
  previewCount: number;
  onContinue: () => void;
  busy: boolean;
}) {
  const { colors } = useTheme();
  const account = accounts.find((a) => a.id === accountId);
  const header = sheet[mapping.headerRow] ?? [];
  const sample = sheet[mapping.headerRow + 1] ?? [];
  const setRole = (i: number, role: ColumnRole) => {
    const columns = mapping.columns.map((r, j) => (j === i ? role : r === role && role !== 'ignore' ? 'ignore' : r));
    onMapping({ ...mapping, columns });
  };
  const hasSingleAmount = mapping.columns.includes('amount') && !mapping.columns.includes('debit');
  return (
    <>
      <GroupHeader title="Statement" />
      <InsetGroup dividerInset={16}>
        <GroupRow title="File" value={fileName} />
        <GroupRow title="Detected" value={template?.name ?? 'Unknown bank'} />
        <Menu items={accounts.map((a) => ({ title: accountLabel(a.name, a.last4), icon: accountIcon(a.type), checked: a.id === accountId, onPress: () => onAccount(a.id) }))}>
          {(open) => <GroupRow title="Import into" value={account ? accountLabel(account.name, account.last4) : 'Choose account'} chevron onPress={open} />}
        </Menu>
      </InsetGroup>

      <GroupHeader title="Columns" />
      <InsetGroup dividerInset={16}>
        {header.map((h, i) => (
          <Menu key={i} items={ROLES.map((r) => ({ title: COLUMN_ROLE_LABEL[r], checked: mapping.columns[i] === r, onPress: () => setRole(i, r) }))}>
            {(open) => (
              <Pressable onPress={open} accessibilityRole="button" style={styles.columnRow}>
                <View style={{ flex: 1 }}>
                  <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
                    {h || `Column ${i + 1}`}
                  </Text>
                  <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
                    e.g. {sample[i] || '—'}
                  </Text>
                </View>
                <Text style={[type.subhead, { color: mapping.columns[i] === 'ignore' ? colors.secondary : colors.accent }]}>
                  {COLUMN_ROLE_LABEL[mapping.columns[i] ?? 'ignore']}
                </Text>
                <Icon name="chevron.up.chevron.down" size={12} color={colors.secondary} />
              </Pressable>
            )}
          </Menu>
        ))}
      </InsetGroup>

      <GroupHeader title="Format" />
      <InsetGroup dividerInset={16}>
        <Menu
          items={[
            { title: 'Day first (01/09 = 1 Sep)', checked: mapping.dateOrder === 'dmy', onPress: () => onMapping({ ...mapping, dateOrder: 'dmy' }) },
            { title: 'Month first (09/01 = 1 Sep)', checked: mapping.dateOrder === 'mdy', onPress: () => onMapping({ ...mapping, dateOrder: 'mdy' }) },
          ]}
        >
          {(open) => <GroupRow title="Dates" value={mapping.dateOrder === 'mdy' ? 'Month first' : 'Day first'} chevron onPress={open} />}
        </Menu>
        {hasSingleAmount ? (
          <Menu
            items={[
              { title: 'Positive = money in', checked: mapping.positiveIs === 'in', onPress: () => onMapping({ ...mapping, positiveIs: 'in' }) },
              { title: 'Positive = money spent', checked: mapping.positiveIs === 'out', onPress: () => onMapping({ ...mapping, positiveIs: 'out' }) },
            ]}
          >
            {(open) => <GroupRow title="Amounts" value={mapping.positiveIs === 'out' ? 'Positive = spent' : 'Positive = money in'} chevron onPress={open} />}
          </Menu>
        ) : null}
      </InsetGroup>

      <Pressable onPress={onContinue} disabled={busy || !accountId || previewCount === 0} accessibilityRole="button" style={{ margin: 16, marginTop: 24 }}>
        <GlassSurface radius={26} tint={colors.accent} interactive style={[styles.cta, { opacity: accountId && previewCount ? 1 : 0.5 }]}>
          <Text style={[type.headline, { color: '#FFFFFF' }]}>
            {previewCount ? `Review ${previewCount} transaction${previewCount === 1 ? '' : 's'}` : 'No transactions found — check the columns'}
          </Text>
        </GlassSurface>
      </Pressable>
    </>
  );
}

function ReviewSummary({ rows, mismatches, fileName, accountName }: { rows: PlannedRow[]; mismatches: number | null; fileName: string; accountName?: string }) {
  const { colors } = useTheme();
  const money = useMoney();
  const included = rows.filter((r) => r.include);
  const out = included.filter((r) => r.row.direction === 'out').reduce((s, r) => s + r.row.amount, 0);
  const inn = included.filter((r) => r.row.direction === 'in').reduce((s, r) => s + r.row.amount, 0);
  const dup = rows.filter((r) => r.status !== 'new').length;
  return (
    <View style={[styles.card, { backgroundColor: colors.card }]}>
      <Text style={[type.footnote, { color: colors.secondary }]} numberOfLines={1}>
        {fileName} → {accountName}
      </Text>
      <View style={styles.tiles}>
        <Stat label="To import" value={String(included.length)} />
        <Stat label="Money out" value={money.amount(out)} />
        <Stat label="Money in" value={money.amount(inn)} />
      </View>
      {dup ? (
        <Text style={[type.footnote, { color: colors.secondary }]}>
          {dup} already in Paisa Pulse {dup === 1 ? 'is' : 'are'} unticked. Tap a row to change anything.
        </Text>
      ) : (
        <Text style={[type.footnote, { color: colors.secondary }]}>Tap a row to change its type, category or to leave it out.</Text>
      )}
      {mismatches ? (
        <Text style={[type.footnote, { color: '#FF9500' }]}>
          {mismatches} row{mismatches === 1 ? '' : 's'} don’t match the running balance. Check the Debit/Credit columns on the previous step.
        </Text>
      ) : null}
    </View>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.tile, { backgroundColor: colors.fill }]}>
      <Text style={[type.caption, { color: colors.secondary }]}>{label}</Text>
      <Text style={[type.subheadAmount, { color: colors.label }]} numberOfLines={1} adjustsFontSizeToFit>
        {value}
      </Text>
    </View>
  );
}

function ReviewList({
  rows,
  accountId,
  onChange,
  header,
  onScroll,
  bottom,
}: {
  rows: PlannedRow[];
  accountId: string;
  onChange: (rows: PlannedRow[]) => void;
  header: React.ReactElement;
  onScroll: (e: { nativeEvent: { contentOffset: { y: number } } }) => void;
  bottom: number;
}) {
  const { colors } = useTheme();
  const money = useMoney();
  const { data: cats } = useQuery(
    async () => ({ expense: await categoriesByKind(appDb, 'expense'), income: await categoriesByKind(appDb, 'income') }),
    [],
    { expense: [], income: [] },
  );
  const { data: accounts } = useQuery(() => accountsWithBalance(appDb), [], []);
  const update = (key: string, patch: Partial<PlannedRow>) => onChange(rows.map((r) => (r.key === key ? { ...r, ...patch } : r)));
  const all = [...cats.expense, ...cats.income];

  return (
    <ScrollView onScroll={onScroll} scrollEventThrottle={16} contentInsetAdjustmentBehavior="never" contentContainerStyle={{ paddingBottom: bottom }}>
      {header}
      <InsetGroup dividerInset={66} style={{ marginTop: 16 }}>
        {rows.map((r) => {
          const cat = all.find((c) => c.id === r.categoryId);
          const other = accounts.find((a) => a.id === r.otherAccountId);
          const kind: TransactionType = r.type;
          const catKind = r.row.direction === 'in' ? 'income' : 'expense';
          const items: MenuItem[] = [
            { title: r.include ? 'Leave Out' : 'Include', icon: r.include ? 'xmark' : 'checkmark', onPress: () => update(r.key, { include: !r.include }) },
            'separator',
            { title: r.row.direction === 'out' ? 'Expense' : 'Income', checked: kind !== 'transfer', onPress: () => update(r.key, { type: r.row.direction === 'out' ? 'expense' : 'income', otherAccountId: null }) },
            ...accounts
              .filter((a) => a.id !== accountId)
              .map((a) => ({
                title: `Transfer ${r.row.direction === 'out' ? 'to' : 'from'} ${a.name}`,
                icon: 'arrow.left.arrow.right',
                checked: kind === 'transfer' && r.otherAccountId === a.id,
                onPress: () => update(r.key, { type: 'transfer' as const, otherAccountId: a.id, categoryId: null }),
              })),
            'separator',
            { title: 'Uncategorised', checked: !r.categoryId && kind !== 'transfer', onPress: () => update(r.key, { categoryId: null, type: r.row.direction === 'out' ? 'expense' : 'income', otherAccountId: null }) },
            ...cats[catKind]
              .filter((c) => !c.parentId)
              .map((c) => ({
                title: c.name,
                icon: c.icon,
                checked: c.id === r.categoryId,
                onPress: () => update(r.key, { categoryId: c.id, type: r.row.direction === 'out' ? 'expense' : 'income', otherAccountId: null }),
              })),
          ];
          const icon = kind === 'transfer' ? 'arrow.left.arrow.right' : (cat?.icon ?? 'questionmark');
          const color = kind === 'transfer' ? TRANSFER_COLOR : (cat?.color ?? UNCATEGORISED_COLOR);
          const detail = [format(r.row.date, 'd MMM'), kind === 'transfer' ? (other ? `${r.row.direction === 'out' ? 'to' : 'from'} ${other.name}` : 'Transfer') : (cat?.name ?? 'Uncategorised')]
            .concat(r.hint && r.status !== 'new' ? [r.hint] : [])
            .join(' · ');
          return (
            <Menu key={r.key} items={items}>
              {(open) => (
                <Pressable
                  onPress={open}
                  onLongPress={() => update(r.key, { include: !r.include })}
                  accessibilityRole="button"
                  accessibilityState={{ checked: r.include }}
                  accessibilityHint="Opens options. Long-press to include or leave out."
                  style={[styles.reviewRow, { backgroundColor: colors.card, opacity: r.include ? 1 : 0.45 }]}
                >
                  <Icon name={r.include ? 'checkmark.circle.fill' : 'circle'} size={22} color={r.include ? colors.accent : colors.secondary} />
                  <CategoryIcon icon={icon} color={color} size={34} />
                  <View style={{ flex: 1, gap: 2 }}>
                    <Text style={[type.body, { color: colors.label }]} numberOfLines={1}>
                      {r.payee ?? r.row.description}
                    </Text>
                    <Text style={[type.footnote, { color: r.status === 'new' ? colors.secondary : '#FF9500' }]} numberOfLines={1}>
                      {detail}
                    </Text>
                  </View>
                  <Text style={[type.bodyAmount, { color: r.row.direction === 'in' && kind !== 'transfer' ? colors.income : colors.label }]}>
                    {money.signed(r.row.amount, kind === 'transfer' ? 'transfer' : r.row.direction === 'in' ? 'income' : 'expense')}
                  </Text>
                </Pressable>
              )}
            </Menu>
          );
        })}
      </InsetGroup>
    </ScrollView>
  );
}

function RecentImports({
  batches,
  onUndo,
  onRestore,
}: {
  batches: Awaited<ReturnType<typeof listImportBatches>>;
  onUndo: (id: string) => void;
  onRestore: (id: string) => void;
}) {
  const { colors } = useTheme();
  if (!batches.length) return <EmptyState icon="square.and.arrow.down" title="No imports yet" message="Imported transactions show up in Activity like any other." />;
  return (
    <>
      <GroupHeader title="Recent imports" />
      <InsetGroup dividerInset={16}>
        {batches.map(({ batch, accountName }) => (
          <Menu
            key={batch.id}
            items={[
              batch.undoneAt
                ? { title: 'Restore Import', icon: 'arrow.uturn.backward.circle.fill', onPress: () => onRestore(batch.id) }
                : { title: 'Undo Import', icon: 'trash', destructive: true, onPress: () => onUndo(batch.id) },
            ]}
          >
            {(open) => (
              <GroupRow
                title={batch.fileName}
                value={`${batch.undoneAt ? 'Undone' : `${batch.count} added`} · ${accountName} · ${format(batch.createdAt, 'd MMM')}`}
                onPress={open}
              />
            )}
          </Menu>
        ))}
      </InsetGroup>
      <Text style={[type.footnote, { color: colors.secondary, paddingHorizontal: 32, paddingTop: 8 }]}>Tap an import to undo it.</Text>
    </>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 16, marginTop: 15, borderRadius: 22, padding: 18, gap: 8 },
  cta: { height: 52, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingHorizontal: 20 },
  error: { marginHorizontal: 16, marginTop: 12, borderRadius: 16, padding: 14, flexDirection: 'row', gap: 10, alignItems: 'center' },
  busy: { alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(0,0,0,0.15)' },
  busyCard: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingHorizontal: 22, height: 60 },
  columnRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 16, paddingVertical: 10, minHeight: 56 },
  tiles: { flexDirection: 'row', gap: 8, marginVertical: 4 },
  tile: { flex: 1, borderRadius: 14, paddingVertical: 10, paddingHorizontal: 12, gap: 2 },
  reviewRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 14, paddingVertical: 10, minHeight: 62 },
  commitBar: { position: 'absolute', left: 16, right: 16 },
  commit: { height: 56, alignItems: 'center', justifyContent: 'center' },
});
