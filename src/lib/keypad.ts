export const OPERATORS = ['+', '−', '×', '÷'];

/** Append a key to a keypad expression, keeping it well-formed ("120+45.5"). */
export function applyKey(expr: string, key: string): string {
  if (key === '⌫') return expr.slice(0, -1);
  if (key === 'C') return '';
  const last = expr.slice(-1);
  const isOp = OPERATORS.includes(key);
  if (isOp) {
    if (expr === '') return expr;
    return OPERATORS.includes(last) ? expr.slice(0, -1) + key : expr + key;
  }
  const current = expr.split(/[+−×÷]/).pop() ?? '';
  if (key === '.') {
    if (current.includes('.')) return expr;
    return expr + (current === '' ? '0.' : '.');
  }
  if (/\.\d\d$/.test(current)) return expr; // two decimals max
  if (current === '0') return expr.slice(0, -1) + key;
  if (current.replace('.', '').length >= 9) return expr; // up to ₹99,99,99,999
  return expr + key;
}
