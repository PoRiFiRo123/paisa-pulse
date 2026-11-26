// Paisa Pulse site: hero SMS → transaction loop, scroll reveals, sticky story, receipt print. No libraries.
(() => {
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s, r = document) => r.querySelector(s);

  // Nav border once scrolled
  const nav = $('.nav');
  addEventListener('scroll', () => nav.classList.toggle('scrolled', scrollY > 8), { passive: true });

  // Reveal on scroll
  const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }), { rootMargin: '0px 0px -10% 0px' });
  document.querySelectorAll('.reveal').forEach((el, i) => { el.style.transitionDelay = `${(i % 4) * 70}ms`; io.observe(el); });

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
  const fmt = (p) => new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(Math.round(p / 100));
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));

  function highlight(text, marks) {
    let html = esc(text);
    marks.forEach((m) => { html = html.replace(esc(m), `<mark>${esc(m)}</mark>`); });
    return html;
  }
  function countTo(from, to, ms = 900) {
    const t0 = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - t0) / ms), e = 1 - Math.pow(1 - k, 3);
      const v = from + (to - from) * e;
      totalEl.textContent = fmt(v);
      leftEl.textContent = '₹' + fmt(Math.max(0, budget - v));
      if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
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
  if (reduce) body.innerHTML = highlight(msgs[0].text, msgs[0].marks);
  else setTimeout(loop, 1300);

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
  setStep(0);

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
