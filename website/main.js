// Home page: hero SMS → transaction loop, live SMS demo, counters, sticky story, screenshot carousel, receipt print. No libraries.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);
  const fmt = (p) => new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(Math.round(p / 100));
  const fmtPaise = (p) => new Intl.NumberFormat('en-IN', { minimumFractionDigits: p % 100 ? 2 : 0, maximumFractionDigits: 2 }).format(p / 100);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const ease = (k) => 1 - Math.pow(1 - k, 3);
  const tween = (ms, fn) => new Promise((done) => {
    if (reduce) { fn(1); return done(); }
    const t0 = performance.now();
    const step = (t) => { const k = Math.min(1, (t - t0) / ms); fn(ease(k)); if (k < 1) requestAnimationFrame(step); else done(); };
    requestAnimationFrame(step);
  });

  // Hero: a bank SMS types in, its key parts light up, then it drops into the list as a transaction.
  const msgs = [
    { text: 'INR 450.00 debited from A/c XX4321 on 26-11 at 1:12 PM. Info- UPI/SWIGGY. Not you? Call 1860…', marks: ['INR 450.00', 'XX4321', 'SWIGGY'],
      row: { mono: 'S', color: '#E8A33D', name: 'Swiggy', meta: 'Food · Axis ••4321', amt: 45000 } },
    { text: 'Rs.80.00 debited from A/c X7556 trf to CHAI POINT Ref 533055556666. -BoB', marks: ['Rs.80.00', 'X7556', 'CHAI POINT'],
      row: { mono: 'C', color: '#B5651D', name: 'Chai Point', meta: 'Food · BoB ••7556', amt: 8000 } },
    { text: 'Spent INR 2,499.00 on Axis Bank Card XX1234 at MYNTRA. Avl Lmt INR 97,501.', marks: ['INR 2,499.00', 'XX1234', 'MYNTRA'],
      row: { mono: 'M', color: '#D9583B', name: 'Myntra', meta: 'Shopping · MyZone', amt: 249900 } },
  ];
  const sms = $('#sms'), body = $('#smsBody'), list = $('#list'), totalEl = $('#total'), bar = $('#bar'), leftEl = $('#left');
  const budget = 4000000;
  let spent = 2486000;

  function highlight(text, marks) {
    let html = esc(text);
    marks.forEach((m) => { html = html.replace(esc(m), `<mark>${esc(m)}</mark>`); });
    return html;
  }
  function countTo(from, to, ms = 900) {
    tween(ms, (e) => {
      const v = from + (to - from) * e;
      totalEl.textContent = fmt(v);
      leftEl.textContent = '₹' + fmt(Math.max(0, budget - v));
    });
  }
  async function play(m) {
    sms.classList.remove('fly'); sms.classList.add('enter');
    body.innerHTML = '';
    for (let i = 1; i <= m.text.length; i += 2) {
      body.innerHTML = esc(m.text.slice(0, i)) + '<span class="caret"></span>';
      await sleep(16);
    }
    body.innerHTML = highlight(m.text, m.marks);
    await sleep(1100);
    sms.classList.remove('enter'); sms.classList.add('fly');
    await sleep(450);
    const li = document.createElement('li');
    li.className = 'new';
    li.innerHTML = `<b class="mono-badge" style="background:${m.row.color}">${m.row.mono}</b><span>${m.row.name}<small>${m.row.meta}</small></span><em>₹${fmt(m.row.amt)}</em>`;
    list.prepend(li);
    while (list.children.length > 4) list.lastElementChild.remove();
    const before = spent; spent += m.row.amt;
    countTo(before, spent);
    bar.style.width = Math.min(100, (spent / budget) * 100).toFixed(1) + '%';
    await sleep(1800);
  }
  async function loop() {
    let i = 0;
    for (;;) {
      if (document.hidden) { await sleep(600); continue; }
      await play(msgs[i % msgs.length]);
      i++;
      if (i % msgs.length === 0) { // start the month over so the numbers stay believable
        spent = 2486000; countTo(spent + msgs.reduce((a, m) => a + m.row.amt, 0), spent, 600); bar.style.width = '62%';
        await sleep(700);
      }
    }
  }
  if (sms) {
    if (reduce) body.innerHTML = highlight(msgs[0].text, msgs[0].marks);
    else setTimeout(loop, 1300);
  }

  // Counters tick to their value when they scroll into view (the zeros count down).
  const co = new IntersectionObserver((es) => es.forEach((e) => {
    if (!e.isIntersecting) return;
    co.unobserve(e.target);
    const el = e.target, from = +(el.dataset.from || 0), to = +el.dataset.to, pre = el.dataset.prefix || '';
    const nf = new Intl.NumberFormat('en-IN');
    tween(1600, (k) => { el.textContent = pre + nf.format(Math.round(from + (to - from) * k)); });
  }), { threshold: 0.6 });
  document.querySelectorAll('.count').forEach((c) => co.observe(c));

  // Live SMS demo: the same rules as the app, run in this page.
  const samples = {
    axis: 'INR 450.00 debited from A/c no. XX4321 on 25-11-26 at 10:15:30 IST. Info- UPI/P2M/533012345678/SWIGGY. Not you? SMS BLOCK 4321 to 919951860002 - Axis Bank',
    bob: 'Rs.199.00 transferred from A/c ...7556 to:UPI/533098765432. Total Bal:Rs.12,345.67CR. Avlbl Amt:Rs.12,345.67(25-11-2026 07:43:21) - Bank of Baroda',
    hdfc: 'Sent Rs.250.00 From HDFC Bank A/C *9999 To Rahul Sharma On 25/11/26 Ref 533011112222 Not You? Call 18002586161',
    card: 'Spent INR 2,499.00 Axis Bank Card no. XX1234 25-11-26 13:45:12 IST at MYNTRA DESIGNS. Avl Lmt INR 97,501.00. Not you? SMS BLOCK 1234',
    salary: 'INR 90,000.00 credited to A/c no. XX4321 on 01-11-26 by NEFT from ACME SOFTWARE PVT LTD. Avl Bal INR 1,02,345.00 - Axis Bank',
    bill: 'Payment of INR 6,400.00 has been received towards your Axis Bank Credit Card XX1234. Thank you.',
    otp: '123456 is your OTP for a transaction of INR 450.00 at SWIGGY. Valid for 10 mins. Do not share it with anyone.',
  };
  const input = $('#smsInput'), out = $('#tryOut');
  const typeLabel = { expense: 'Expense', income: 'Income', transfer: 'Card bill · Transfer' };
  let lastKey = '';

  function renderDraft(d) {
    const name = d.payee || (d.type === 'transfer' ? 'Credit card bill' : 'Unknown payee');
    const mono = (name.match(/[a-z0-9]/i) || ['?'])[0].toUpperCase();
    const color = d.brandColor || (d.type === 'income' ? '#2F7A5A' : d.type === 'transfer' ? '#8A8377' : '#5E5A52');
    const acct = [d.bank || (d.accountKind === 'card' ? 'Card' : 'Account'), d.last4 ? `••${d.last4}` : ''].join(' ').trim();
    const ref = d.key.startsWith('alert:') && !/^alert:\d+:/.test(d.key) ? `Ref ${d.key.slice(6)}` : 'From the message text';
    const rows = [
      ['Category', d.category || (d.type === 'transfer' ? 'None (it\'s a transfer)' : 'You pick')],
      [d.type === 'transfer' ? 'Paid to' : 'Account', d.type === 'transfer' ? `Card ${d.last4 ? '••' + d.last4 : ''}`.trim() : acct],
      ['Paid with', d.method || '—'],
      ['Duplicate check', ref],
    ];
    out.innerHTML = `
      <div class="draft-card t-${d.type}">
        <div class="dc-top">
          <b class="mono-badge" style="background:${esc(color)}">${esc(mono)}</b>
          <span class="dc-name"><b title="${esc(name)}">${esc(name)}</b><small>${esc(typeLabel[d.type])}</small></span>
          <em class="dc-amt">₹<span id="dcAmt">0</span></em>
        </div>
        <dl class="dc-rows">${rows.map(([k, v], i) => `<div style="--i:${i}"><dt>${esc(k)}</dt><dd>${esc(v)}</dd></div>`).join('')}</dl>
        <p class="dc-foot">In the app, this waits as a draft. One tap adds it.</p>
      </div>`;
    const amtEl = $('#dcAmt');
    tween(700, (k) => { amtEl.textContent = k < 1 ? fmt(d.amount * k) : fmtPaise(d.amount); });
  }
  function renderSkip(reason) {
    out.innerHTML = `<div class="skip-card"><svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M6 18 18 6" stroke="currentColor" stroke-width="2"/></svg><p>${esc(reason)}</p></div>`;
  }
  function run() {
    if (!globalThis.PaisaParser) return;
    const text = input.value;
    if (!text.trim()) { out.innerHTML = '<p class="try-empty">Pick a sample above, or paste a message.</p>'; lastKey = ''; return; }
    const r = PaisaParser.parse(text);
    const k = JSON.stringify(r);
    if (k === lastKey) return;
    lastKey = k;
    if (r.draft) renderDraft(r.draft); else renderSkip(r.skipped);
  }
  if (input) {
    // Tapping the box on a phone: once the keyboard is up, park the box just under the top bar so it and the keyboard both show.
    const vv = window.visualViewport;
    const park = () => {
      const nav = document.querySelector('.nav');
      const top = (nav ? nav.getBoundingClientRect().bottom : 0) + 10;
      const label = input.previousElementSibling || input;
      const y = label.getBoundingClientRect().top + scrollY - top;
      scrollTo({ top: Math.max(0, y), behavior: reduce ? 'auto' : 'smooth' });
    };
    input.addEventListener('focus', () => {
      if (!matchMedia('(pointer: coarse)').matches) return;
      let done = false;
      const once = () => { if (done) return; done = true; vv && vv.removeEventListener('resize', once); setTimeout(park, 60); };
      if (vv) vv.addEventListener('resize', once);
      setTimeout(once, 450); // in case the keyboard was already open
    });
    let t;
    input.addEventListener('input', () => { clearTimeout(t); t = setTimeout(run, 180); });
    document.querySelectorAll('[data-sample]').forEach((b) => b.addEventListener('click', async () => {
      document.querySelectorAll('[data-sample]').forEach((x) => x.classList.toggle('on', x === b));
      const text = samples[b.dataset.sample];
      if (reduce) { input.value = text; run(); out.scrollIntoView({ block: 'nearest' }); return; }
      input.value = '';
      for (let i = 0; i <= text.length; i += 4) { input.value = text.slice(0, i); await sleep(8); }
      input.value = text; run();
      // On phones the result sits below the chips: bring it into view.
      const r = out.getBoundingClientRect();
      if (r.bottom > innerHeight) out.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
    }));
  }

  // Sticky story: the step nearest the middle of the screen drives the phone.
  const steps = [...document.querySelectorAll('.step')];
  const scrs = [...document.querySelectorAll('.scr')];
  const dots = [...document.querySelectorAll('.dots i')];
  const setStep = (n) => {
    steps.forEach((s, i) => s.classList.toggle('active', i === n));
    scrs.forEach((s, i) => s.classList.toggle('on', i === n));
    dots.forEach((d, i) => d.classList.toggle('on', i === n));
  };
  const so = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) setStep(+e.target.dataset.step); }), { rootMargin: '-58% 0px -32% 0px' });
  steps.forEach((s) => so.observe(s));
  if (steps.length) setStep(0);

  // Screenshot carousel: phones turn in 3D as they move away from the centre; drag with a mouse, swipe on touch.
  const car = $('#carousel');
  if (car) {
    const shots = [...car.querySelectorAll('.shot')];
    let raf = 0;
    const update = () => {
      raf = 0;
      const mid = car.getBoundingClientRect().left + car.clientWidth / 2;
      shots.forEach((s) => {
        const r = s.getBoundingClientRect();
        const off = Math.max(-1.6, Math.min(1.6, (r.left + r.width / 2 - mid) / r.width));
        s.style.setProperty('--off', off.toFixed(3));
        s.classList.toggle('centre', Math.abs(off) < 0.5);
      });
    };
    const queue = () => { if (!raf) raf = requestAnimationFrame(update); };
    car.addEventListener('scroll', queue, { passive: true });
    addEventListener('resize', queue);
    // Start on the second phone so there's something either side.
    requestAnimationFrame(() => { car.scrollLeft = shots[1] ? shots[1].offsetLeft - (car.clientWidth - shots[1].offsetWidth) / 2 : 0; update(); });
    // Mouse drag
    let down = null;
    car.addEventListener('pointerdown', (e) => { if (e.pointerType !== 'mouse') return; down = { x: e.clientX, s: car.scrollLeft }; car.classList.add('dragging'); });
    addEventListener('pointermove', (e) => { if (down) car.scrollLeft = down.s - (e.clientX - down.x); });
    addEventListener('pointerup', () => { if (down) { down = null; car.classList.remove('dragging'); } });
    car.addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      e.preventDefault();
      car.scrollBy({ left: (e.key === 'ArrowRight' ? 1 : -1) * shots[0].offsetWidth, behavior: reduce ? 'auto' : 'smooth' });
    });
  }

  // Receipt prints as it scrolls into view.
  const receipt = $('#receipt');
  if (receipt && !reduce) {
    const print = () => {
      const r = receipt.getBoundingClientRect(), vh = innerHeight;
      const k = Math.min(1, Math.max(0, (vh - r.top) / (vh * 0.75)));
      receipt.style.setProperty('--cut', `${(1 - k) * 100}%`);
    };
    addEventListener('scroll', print, { passive: true }); print();
  }
})();
