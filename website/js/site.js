// Shared by every page: theme toggle, nav border, device-aware download links, magnetic buttons, scroll reveals.
(() => {
  const root = document.documentElement;
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const systemDark = matchMedia('(prefers-color-scheme: dark)');

  // Theme: follows the phone or computer setting until you pick one.
  const isDark = () => (root.dataset.theme ? root.dataset.theme === 'dark' : systemDark.matches);
  const syncThemeUI = () => {
    const dark = isDark();
    document.querySelectorAll('[data-theme-toggle]').forEach((b) => b.setAttribute('aria-label', dark ? 'Switch to light mode' : 'Switch to dark mode'));
    document.querySelectorAll('meta[name="theme-color"]').forEach((m) => m.setAttribute('content', dark ? '#12110E' : '#F3EEE4'));
  };
  document.querySelectorAll('[data-theme-toggle]').forEach((b) => b.addEventListener('click', () => {
    const next = isDark() ? 'light' : 'dark';
    const apply = () => { root.dataset.theme = next; syncThemeUI(); };
    try { localStorage.setItem('theme', next); } catch (e) { /* private mode */ }
    if (document.startViewTransition && !reduce) document.startViewTransition(apply); else apply();
  }));
  systemDark.addEventListener('change', syncThemeUI);
  syncThemeUI();

  // Nav border once scrolled
  const nav = document.querySelector('.nav');
  if (nav) addEventListener('scroll', () => nav.classList.toggle('scrolled', scrollY > 8), { passive: true });

  // Phone menu: opens under the pill; closes on a link, Escape, a tap outside, or growing the window.
  const menuBtn = document.querySelector('[data-menu]');
  if (nav && menuBtn) {
    const setOpen = (open) => {
      nav.classList.toggle('open', open);
      menuBtn.setAttribute('aria-expanded', String(open));
      menuBtn.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    };
    menuBtn.addEventListener('click', (e) => { e.stopPropagation(); setOpen(!nav.classList.contains('open')); });
    nav.querySelectorAll('nav a').forEach((a) => a.addEventListener('click', () => setOpen(false)));
    addEventListener('keydown', (e) => { if (e.key === 'Escape' && nav.classList.contains('open')) { setOpen(false); menuBtn.focus(); } });
    document.addEventListener('click', (e) => { if (!nav.contains(e.target)) setOpen(false); });
    matchMedia('(min-width: 861px)').addEventListener('change', () => setOpen(false));
    addEventListener('scroll', () => { if (nav.classList.contains('open') && Math.abs(scrollY - (nav._y ?? scrollY)) > 60) setOpen(false); nav._y = nav.classList.contains('open') ? (nav._y ?? scrollY) : undefined; }, { passive: true });
  }

  // Highlight the section you're reading in the pill.
  const links = [...document.querySelectorAll('.nav nav a[href^="#"]')];
  const targets = links.map((a) => document.querySelector(a.getAttribute('href'))).filter(Boolean);
  if (targets.length) {
    const seen = new Map();
    const so = new IntersectionObserver((es) => {
      es.forEach((e) => seen.set(e.target, e.isIntersecting));
      const cur = targets.find((t) => seen.get(t));
      links.forEach((a) => a.classList.toggle('on', !!cur && a.getAttribute('href') === '#' + cur.id));
    }, { rootMargin: '-45% 0px -50% 0px' });
    targets.forEach((t) => so.observe(t));
  }

  // Which phone is this? Download buttons go straight to the right thing.
  const ua = navigator.userAgent;
  const device = /android/i.test(ua) ? 'android' : /iphone|ipad|ipod/i.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1) ? 'iphone' : 'desktop';
  root.dataset.device = device;
  const APK = 'https://github.com/PoRiFiRo123/paisa-pulse/releases/latest/download/PaisaPulse.apk';
  document.querySelectorAll('[data-download]').forEach((a) => {
    const label = a.querySelector('[data-download-label]');
    if (device === 'android') { a.href = APK; if (label) label.textContent = 'Download for Android'; }
    else if (device === 'iphone') { a.href = '/download#iphone'; if (label) label.textContent = 'Get it on iPhone'; }
    else { a.href = '/download'; if (label) label.textContent = 'Get the app'; }
  });
  globalThis.PaisaDevice = { device, APK };

  // Buttons lean towards the cursor (mouse and trackpad only).
  if (!reduce && matchMedia('(pointer: fine)').matches) {
    document.querySelectorAll('.magnetic').forEach((el) => {
      el.addEventListener('pointermove', (e) => {
        const r = el.getBoundingClientRect();
        const x = (e.clientX - r.left - r.width / 2) / r.width, y = (e.clientY - r.top - r.height / 2) / r.height;
        el.style.transform = `translate(${x * 10}px, ${y * 8}px)`;
      });
      el.addEventListener('pointerleave', () => { el.style.transform = ''; });
    });
  }

  // Reveal on scroll
  const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } }), { rootMargin: '0px 0px -10% 0px' });
  document.querySelectorAll('.reveal').forEach((el, i) => { el.style.transitionDelay = `${(i % 4) * 70}ms`; io.observe(el); });
})();
