import { Asset } from 'expo-asset';
import { File } from 'expo-file-system';
import { createContext, type ReactNode, useCallback, useContext, useEffect, useRef, useState } from 'react';
import { Platform, StyleSheet, View } from 'react-native';
import { WebView, type WebViewMessageEvent } from 'react-native-webview';

import type { TextItem } from './readers/pdfLayout';

export type PdfResult = { ok: true; items: TextItem[]; pages: number } | { ok: false; error: string };
type Extract = (base64: string, password?: string) => Promise<PdfResult>;

const PdfContext = createContext<Extract | null>(null);

/**
 * Hosts a hidden WebView running pdf.js (assets/pdf/extractor.html). PDFs are read
 * entirely on the device; nothing is uploaded.
 */
export function PdfExtractorProvider({ children }: { children: ReactNode }) {
  const [html, setHtml] = useState<string | null>(null);
  const web = useRef<WebView>(null);
  const ready = useRef<Promise<void> | null>(null);
  const markReady = useRef<() => void>(() => {});
  const pending = useRef(new Map<string, (r: PdfResult) => void>());

  useEffect(() => {
    ready.current = new Promise((resolve) => (markReady.current = resolve));
    // react-native-webview has no web implementation (web is only a preview target).
    if (Platform.OS === 'web') return;
    (async () => {
      const asset = Asset.fromModule(require('../../../assets/pdf/extractor.html'));
      await asset.downloadAsync();
      setHtml(await new File(asset.localUri ?? asset.uri).text());
    })().catch((e) => console.warn('pdf extractor failed to load', e));
  }, []);

  const onMessage = useCallback((e: WebViewMessageEvent) => {
    const msg = JSON.parse(e.nativeEvent.data) as { ready?: boolean; id?: string } & PdfResult;
    if (msg.ready) markReady.current();
    if (msg.id) {
      pending.current.get(msg.id)?.(msg);
      pending.current.delete(msg.id);
    }
  }, []);

  const extract = useCallback<Extract>(async (base64, password) => {
    if (Platform.OS === 'web') return { ok: false, error: 'PDF statements can be imported in the iPhone and Android app.' };
    await ready.current;
    const id = Math.random().toString(36).slice(2);
    return new Promise<PdfResult>((resolve) => {
      pending.current.set(id, resolve);
      web.current?.postMessage(JSON.stringify({ id, base64, password }));
      setTimeout(() => {
        if (pending.current.delete(id)) resolve({ ok: false, error: 'Reading the PDF took too long.' });
      }, 60_000);
    });
  }, []);

  return (
    <PdfContext.Provider value={extract}>
      {children}
      {html ? (
        <View style={styles.hidden} pointerEvents="none">
          <WebView
            ref={web}
            source={{ html, baseUrl: 'https://paisapulse.local/' }}
            originWhitelist={['*']}
            javaScriptEnabled
            onMessage={onMessage}
            // Reading PDFs needs no network; block any navigation away.
            onShouldStartLoadWithRequest={(r) => r.url.startsWith('https://paisapulse.local') || r.url.startsWith('about:')}
          />
        </View>
      ) : null}
    </PdfContext.Provider>
  );
}

export function usePdfExtractor(): Extract {
  const ctx = useContext(PdfContext);
  if (!ctx) throw new Error('usePdfExtractor must be inside PdfExtractorProvider');
  return ctx;
}

const styles = StyleSheet.create({ hidden: { position: 'absolute', width: 1, height: 1, opacity: 0, left: -10, top: -10 } });
