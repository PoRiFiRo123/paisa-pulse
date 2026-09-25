import { strToU8, zipSync } from 'fflate';

import { parseCsv } from '../readers/csv';
import { detectFileKind } from '../readers/detect';
import { readHtmlTable } from '../readers/html';
import { readXlsx } from '../readers/xlsx';

describe('parseCsv', () => {
  it('handles quotes, escaped quotes, CRLF, BOM and empty lines', () => {
    const csv = '﻿Date,Narration,Amount\r\n01/09/2026,"UPI/SWIGGY, Koramangala","1,250.50"\r\n\r\n02/09/2026,"He said ""hi""",10\n';
    expect(parseCsv(csv)).toEqual([
      ['Date', 'Narration', 'Amount'],
      ['01/09/2026', 'UPI/SWIGGY, Koramangala', '1,250.50'],
      ['02/09/2026', 'He said "hi"', '10'],
    ]);
  });

  it('detects semicolon and tab delimiters', () => {
    expect(parseCsv('a;b;c\n1;2,5;3\n4;5;6')).toEqual([['a', 'b', 'c'], ['1', '2,5', '3'], ['4', '5', '6']]);
    expect(parseCsv('a\tb\n1\t2')).toEqual([['a', 'b'], ['1', '2']]);
  });

  it('keeps newlines inside quoted cells', () => {
    expect(parseCsv('x,y\n"line1\nline2",2')).toEqual([['x', 'y'], ['line1\nline2', '2']]);
  });
});

describe('readXlsx', () => {
  it('reads shared strings, inline strings, numbers and sparse columns', () => {
    const files = {
      'xl/workbook.xml': strToU8('<workbook><sheets><sheet name="Statement" sheetId="1" r:id="rId1"/></sheets></workbook>'),
      'xl/_rels/workbook.xml.rels': strToU8('<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>'),
      'xl/sharedStrings.xml': strToU8('<sst><si><t>Tran Date</t></si><si><t>PARTICULARS</t></si><si><r><t>UPI/SWIGGY</t></r><r><t> &amp; Co</t></r></si></sst>'),
      'xl/worksheets/sheet1.xml': strToU8(
        '<worksheet><sheetData>' +
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="D1" t="inlineStr"><is><t>DR</t></is></c></row>' +
          '<row r="2"><c r="A2"><v>46266</v></c><c r="B2" t="s"><v>2</v></c><c r="D2"><v>420.5</v></c></row>' +
          '</sheetData></worksheet>',
      ),
    };
    expect(readXlsx(zipSync(files))).toEqual([
      ['Tran Date', 'PARTICULARS', '', 'DR'],
      ['46266', 'UPI/SWIGGY & Co', '', '420.5'],
    ]);
  });
});

describe('readHtmlTable', () => {
  it('reads the largest table with entities, breaks and colspans', () => {
    const html = '<html><table><tr><td>Logo</td></tr></table><table><tr><th>Date</th><th colspan="2">Narration</th></tr><tr><td>01/09/26</td><td>NEFT&nbsp;SALARY<br>ACME</td><td>x</td></tr></table></html>';
    expect(readHtmlTable(html)).toEqual([
      ['Date', 'Narration', ''],
      ['01/09/26', 'NEFT SALARY ACME', 'x'],
    ]);
  });
});

describe('detectFileKind', () => {
  const bytes = (s: string) => new TextEncoder().encode(s);
  it('recognises files by content, not extension', () => {
    expect(detectFileKind(bytes('%PDF-1.7'))).toBe('pdf');
    expect(detectFileKind(new Uint8Array([0x50, 0x4b, 3, 4]))).toBe('xlsx');
    expect(detectFileKind(new Uint8Array([0xd0, 0xcf, 0x11, 0xe0, 0xa1]))).toBe('xls-binary');
    expect(detectFileKind(bytes('<html><body><table>'))).toBe('html');
    expect(detectFileKind(bytes('Date,Amount\n'))).toBe('csv');
  });
});
