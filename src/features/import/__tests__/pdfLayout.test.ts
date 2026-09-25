import { layoutToSheet, type TextItem } from '../readers/pdfLayout';

// Build items like pdf.js would: words positioned on a page.
const word = (str: string, x: number, y: number, page = 1): TextItem => ({ str, x, y, w: str.length * 5, h: 9, page });

describe('layoutToSheet', () => {
  it('rebuilds columns from the header and folds wrapped narrations', () => {
    const items = [
      word('Axis Bank Statement', 40, 20),
      word('Tran', 40, 60), word('Date', 63, 60),
      word('Particulars', 140, 60),
      word('Debit', 360, 60), word('Credit', 430, 60), word('Balance', 500, 60),
      word('01-09-2026', 40, 80), word('UPI/P2M/412345/SWIGGY', 140, 80), word('420.00', 365, 80), word('9,580.00', 505, 80),
      word('LIMITED/Payment', 140, 91),
      word('02-09-2026', 40, 110), word('NEFT/SALARY/ACME', 140, 110), word('90,000.00', 430, 110), word('99,580.00', 500, 110),
      // Page 2 repeats the header.
      word('Tran', 40, 60, 2), word('Date', 63, 60, 2), word('Particulars', 140, 60, 2), word('Debit', 360, 60, 2), word('Credit', 430, 60, 2), word('Balance', 500, 60, 2),
      word('03-09-2026', 40, 80, 2), word('ATM-WDL/MG ROAD', 140, 80, 2), word('2,000.00', 362, 80, 2), word('97,580.00', 500, 80, 2),
    ];
    expect(layoutToSheet(items)).toEqual([
      ['Tran Date', 'Particulars', 'Debit', 'Credit', 'Balance'],
      ['01-09-2026', 'UPI/P2M/412345/SWIGGY LIMITED/Payment', '420.00', '', '9,580.00'],
      ['02-09-2026', 'NEFT/SALARY/ACME', '', '90,000.00', '99,580.00'],
      ['03-09-2026', 'ATM-WDL/MG ROAD', '2,000.00', '', '97,580.00'],
    ]);
  });
});

describe('layoutToSheet on a real pdf.js extraction', () => {
  // Items extracted by assets/pdf/extractor.html from a printed Axis-style statement whose
  // cells are vertically centred (narrations wrap above and below the date line).
  it('keeps each wrapped narration with its own row', () => {
    const items = require('./fixtures/axis-pdf-items.json') as TextItem[];
    const sheet = layoutToSheet(items);
    expect(sheet[0]).toEqual(['Tran Date', 'Particulars', 'Debit', 'Credit', 'Balance']);
    expect(sheet.slice(1).map((r) => [r[0], r[1], r[2], r[3], r[4]])).toEqual([
      ['01-09-2026', 'OPENING BALANCE', '', '', '10,000.00'],
      ['01-09-2026', 'UPI/P2M/424412345678/SWIGGY LIMITED/swiggy@icici/Payment for order 88231', '420.00', '', '9,580.00'],
      ['02-09-2026', 'NEFT/N245260123456/ACME TECHNOLOGIES PVT LTD/SALARY SEP', '', '90,000.00', '99,580.00'],
      ['03-09-2026', 'ATM-WDL/MG ROAD BANGALORE/S1AW0123', '2,000.00', '', '97,580.00'],
      ['05-09-2026', 'BILLDESK/AXIS BANK CREDIT CARD/XX3307 PAYMENT', '8,360.00', '', '89,220.00'],
      ['06-09-2026', 'UPI/P2A/424912345/RAHUL SHARMA/rahul@okaxis/rent share', '7,500.00', '', '81,720.00'],
      // Prose under the table stays one cell; the normaliser drops it (no date).
      ['Closing Balance 81,720.00', '', '', '', ''],
    ]);
  });
});
