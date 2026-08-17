// Casberi site behavior — two things only:
// 1. Hero: the app icons rain in (CSS), sit a beat, fly INTO the Casberi
//    tile (which pulses as it takes them), then rain back down and REST.
//    The story plays once; tapping the Casberi tile replays it.
// 2. Scroll reveal: walkthrough sections fade up the first time they enter
//    the viewport. Content is fully visible without JS.

// Lazy-play: videos autoplay, but the observer pauses any that scroll out of
// view and resumes them when they return — so off-screen clips don't burn
// CPU/battery, and only what you're looking at is running.
(function lazyVideos() {
  var vids = Array.prototype.slice.call(document.querySelectorAll('video'));
  if (!vids.length || !('IntersectionObserver' in window)) return;
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) { e.target.play().catch(function () {}); }
      else { e.target.pause(); }
    });
  }, { threshold: 0.25 });
  vids.forEach(function (v) { io.observe(v); });
})();

(function hero() {
  var rain = document.querySelector('.rain');
  var target = document.querySelector('.rain-target .ai-casberi');
  var em = document.querySelector('.hero h1 em');
  if (!rain || !target) return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  var icons = Array.prototype.slice.call(rain.children);
  var state = 'raining';          // raining → absorbing → rested
  // How much the mark swells at the peak of the gather, as a fraction of its
  // 52px resting size. The original 0.10 read as a beat; 0.80 read as a swell;
  // 4.0 reads as the thing actually eating the page — 52px becomes ~260px,
  // which fills the space the rain just vacated instead of merely nodding at
  // it. That only works because the growth is a TRANSFORM: it takes no layout
  // room, so nothing below it reflows no matter how large it gets.
  var SWELL = 4.0;

  // Act 2 — gather. Icons leave far-first in a rolling wave, curve along an
  // arc, accelerate into the tile, and recede (scale + fade) as they arrive.
  // Each arrival feeds the berry: the tile grows a little and gulps.
  function absorb() {
    if (state === 'absorbing') return;
    state = 'absorbing';
    var t = target.getBoundingClientRect();
    var tx = t.left + t.width / 2, ty = t.top + t.height / 2;
    var infos = icons.map(function (el) {
      var r = el.getBoundingClientRect();
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      return { el: el, dx: tx - cx, dy: ty - cy, d: Math.hypot(tx - cx, ty - cy) };
    });
    infos.sort(function (a, b) { return b.d - a.d; });
    var n = infos.length, done = 0;
    infos.forEach(function (o, rank) {
      var mx = o.dx * 0.55 - o.dy * 0.16;   // arc: midpoint pushed off the line
      var my = o.dy * 0.55 + o.dx * 0.16;
      var anim = o.el.animate([
        { transform: 'translate(0px,0px) scale(1)', opacity: 1, easing: 'cubic-bezier(.3,0,.7,.4)' },
        { transform: 'translate(0px,-8px) scale(1.05)', opacity: 1, offset: 0.14, easing: 'cubic-bezier(.4,0,.9,.4)' },
        { transform: 'translate(' + mx + 'px,' + my + 'px) scale(.72)', opacity: .95, offset: 0.62, easing: 'cubic-bezier(.5,0,.95,.5)' },
        { transform: 'translate(' + o.dx + 'px,' + o.dy + 'px) scale(.08)', opacity: 0 }
      ], { duration: 680, delay: rank * 26, fill: 'forwards' });
      anim.onfinish = function () {
        done++;
        // Conservation of mass: the octopus grows with every app it drinks,
        // and the growth EASES OUT rather than running linearly — a creature
        // filling up gains most of its size early and then strains for the
        // last of it. Linear growth reads as a progress bar; this reads as
        // eating. 52px -> ~93px at the top of the swell.
        var fill = done / n;
        var eased = 1 - Math.pow(1 - fill, 2.2);
        // The standalone `scale` property, NOT transform. `fall` is a CSS
        // animation on this element with fill:both, so it owns `transform`
        // forever — and a CSS animation outranks an inline style, which is
        // why every earlier attempt to set style.transform here was silently
        // discarded. `scale` composes independently, the same way berryBob
        // already uses `translate`.
        target.style.scale = (1 + SWELL * eased).toFixed(3);
        // Every arrival gulps, and the gulp SHRINKS as the creature fills:
        // a small animal takes a big swallow, a full one barely flinches.
        target.animate(
          [{ transform: 'scale(1)' },
           { transform: 'scale(' + (1 + 0.055 * (1 - eased * 0.75)).toFixed(3) + ')' },
           { transform: 'scale(1)' }],
          { duration: 190, easing: 'cubic-bezier(.3,1.4,.6,1)', composite: 'add' });
        if (done === n) finale();
      };
    });
  }

  // Act 3 — payoff. The berry settles, then STREAMS: abstract feed cards
  // materialize above it like generated UI — every size and shape, none
  // wearing an app's badge. App logos here read as "this is the whole
  // catalog"; shapes read as "your feed takes any shape" (2026-07-14).
  function finale() {
    setTimeout(function () {
      // the energy flows out: the berry springs back to size…
      target.style.scale = '1';
      // The release. It gives back everything it took, so this overshoots the
      // other way — the squash is what sells the size it just lost, and the
      // duration is longer than the gulps so the eye reads it as one motion
      // settling rather than another bite.
      target.animate(
        [{ transform: 'scale(1.10)' }, { transform: 'scale(.90)' },
         { transform: 'scale(1.03)' }, { transform: 'scale(1)' }],
        { duration: 620, easing: 'cubic-bezier(.34,1.56,.64,1)', composite: 'add' });
      // …and becomes a feed, streaming into the space the rain left behind
      rain.style.position = 'relative';
      var panel = document.createElement('div');
      panel.className = 'streamfeed';
      rain.appendChild(panel);
      var rr = rain.getBoundingClientRect();
      var vw = Math.min(window.innerWidth, 1900);
      panel.style.width = vw + 'px';
      // rows of uneven heights, each dealing 2–4 cards of uneven widths;
      // per-card nudges knock everything off the row line so the wall reads
      // scattered, not gridded. Rows fill the rain's height, never clipping.
      var rowPatterns = [
        { h: 62, w: [3, 2, 4], indent: 0 },
        { h: 92, w: [2, 5], indent: 26 },
        { h: 46, w: [4, 3, 2, 3], indent: 8 },
        { h: 76, w: [5, 3], indent: 34 },
        { h: 56, w: [2, 3, 2], indent: 14 },
        { h: 86, w: [3, 4], indent: 4 }
      ];
      var inner = [
        '<span class="sbar" style="width:0"></span><span class="sbar thin" style="width:0"></span>',
        '<span class="sblock t1"></span><span class="sbar thin" style="width:0"></span>',
        '<span class="sbar" style="width:0"></span>',
        '<span class="sblock t2"></span>',
        '<span class="sbar" style="width:0"></span><span class="sbar thin" style="width:0"></span><span class="sbar thin" style="width:0"></span>',
        '<span class="sblock t3"></span><span class="sbar" style="width:0"></span>',
        '<span class="sbar thin" style="width:0"></span><span class="sblock t4"></span>'
      ];
      var barWidths = [62, 38, 44, 70, 30, 52, 40, 58, 34, 66, 26, 48];
      var nudge = [-8, 5, -3, 9, -6, 2, 7, -9, 4, -5];
      var gapY = 16, cards = [], y = 8, ri = 0, ci = 0, bi = 0;
      while (cards.length < 40) {
        var pat = rowPatterns[ri % rowPatterns.length];
        if (y + pat.h > rr.height - 8) break;
        var row = document.createElement('div');
        row.className = 'streamline';
        row.style.height = pat.h + 'px';
        row.style.paddingLeft = pat.indent + 'px';
        row.style.paddingRight = (34 - pat.indent) + 'px';
        // narrow screens: two cards a row is plenty
        var flexes = vw < 520 ? pat.w.slice(0, 2) : pat.w;
        flexes.forEach(function (flex) {
          var card = document.createElement('div');
          card.className = 'scard';
          card.style.flex = flex + ' 1 0';
          card.style.marginTop = nudge[ci % nudge.length] + 'px';
          card.innerHTML = inner[ci % inner.length];
          ci++;
          row.appendChild(card);
          cards.push(card);
        });
        panel.appendChild(row);
        y += pat.h + gapY;
        ri++;
      }
      var tRect = target.getBoundingClientRect();
      var tcx = tRect.left + tRect.width / 2, tcy = tRect.top + tRect.height / 2;
      cards.forEach(function (card) {
        var b = card.getBoundingClientRect();
        var dx = tcx - (b.left + b.width / 2), dy = tcy - (b.top + b.height / 2);
        card.style.transform = 'translate(' + dx + 'px,' + dy + 'px) scale(.2)';
      });
      cards.forEach(function (card, k) {
        setTimeout(function () {
          card.classList.add('in');
          card.style.transform = '';
          var bars = card.querySelectorAll('.sbar');
          Array.prototype.forEach.call(bars, function (bar, j) {
            var w = barWidths[bi % barWidths.length];
            bi++;
            setTimeout(function () { bar.style.width = w + '%'; }, 170 + j * 150);
          });
        }, 45 * k);
      });
      if (em) setTimeout(function () { em.classList.add('lit'); }, 45 * cards.length + 500);
      setTimeout(function () { state = 'rested'; }, 45 * cards.length + 900);
    }, 380);   // a beat at full size before the release
  }

  // Replay — tap the berry: everything scatters back out, then gathers again.
  function replay() {
    if (state !== 'rested') return;
    state = 'raining';
    if (em) em.classList.remove('lit');
    var panel = rain.querySelector('.streamfeed');
    if (panel) panel.remove();
    target.style.transform = '';
    target.style.scale = '';        // the swell rides `scale` — clear it too
    icons.forEach(function (el, i) {
      el.getAnimations().forEach(function (a) { a.cancel(); });
      el.style.animation = 'none';
      void el.offsetWidth;               // reflow so the CSS rain restarts
      el.style.animation = '';
      el.style.animationDelay = (0.05 + i * 0.04) + 's';
    });
    setTimeout(absorb, icons.length * 40 + 1400);
  }

  target.style.cursor = 'pointer';
  target.title = 'Tap to replay';
  target.addEventListener('click', replay);

  setTimeout(absorb, 3000);   // the story plays once, then rests
})();

(function scrollSpy() {
  var links = Array.prototype.slice.call(document.querySelectorAll('.nav-links a[href^="#"]'));
  if (!links.length || !('IntersectionObserver' in window)) return;
  var byId = {};
  links.forEach(function (a) { byId[a.getAttribute('href').slice(1)] = a; });
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      links.forEach(function (a) { a.classList.remove('on'); });
      var a = byId[e.target.id];
      if (a) a.classList.add('on');
    });
  }, { rootMargin: '-30% 0px -60% 0px' });
  Object.keys(byId).forEach(function (id) {
    var sec = document.getElementById(id);
    if (sec) io.observe(sec);
  });
})();

(function scrollReveal() {
  if (!('IntersectionObserver' in window)) return;
  var els = document.querySelectorAll('.step-copy, .step-mock, .phone-row, .store-sec, .catalog-head, .final-cta');
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) {
        e.target.classList.add('in');
        io.unobserve(e.target);
      }
    });
  }, { threshold: 0.15 });
  els.forEach(function (el) {
    el.classList.add('reveal');
    io.observe(el);
  });
})();

// Tour delight: tilt, glow, letter cascades, hellos, icon confetti,
// magnetic CTA, tap-to-pause. All gated behind prefers-reduced-motion.
(function delight() {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  // Phones tilt toward the cursor
  document.querySelectorAll('.vid, .vid-full').forEach(function (ph) {
    var card = ph.closest('.b-hero') || ph.parentElement;
    card.addEventListener('mousemove', function (e) {
      var r = ph.getBoundingClientRect();
      var dx = (e.clientX - (r.left + r.width / 2)) / r.width;
      var dy = (e.clientY - (r.top + r.height / 2)) / r.height;
      ph.style.transform = 'rotateY(' + (dx * 10) + 'deg) rotateX(' + (-dy * 8) + 'deg)';
    });
    card.addEventListener('mouseleave', function () { ph.style.transform = ''; });
  });

  // Blue card glow follows the cursor
  document.querySelectorAll('.b-hero.loud').forEach(function (card) {
    card.addEventListener('mousemove', function (e) {
      var r = card.getBoundingClientRect();
      card.style.setProperty('--mx', ((e.clientX - r.left) / r.width * 100) + '%');
      card.style.setProperty('--my', ((e.clientY - r.top) / r.height * 100) + '%');
    });
  });

  // Eyebrow letters cascade in; sections fade up
  document.querySelectorAll('.m-eyebrow').forEach(function (eb) {
    var text = eb.textContent;
    eb.textContent = '';
    text.split('').forEach(function (ch, i) {
      var sp = document.createElement('span');
      sp.textContent = ch === ' ' ? '\u00a0' : ch;
      sp.style.transitionDelay = (i * 28) + 'ms';
      eb.appendChild(sp);
    });
  });
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (!e.isIntersecting) return;
      e.target.classList.add('in');
      var eb = e.target.querySelector('.m-eyebrow');
      if (eb) eb.classList.add('in');
      io.unobserve(e.target);
    });
    // A RATIO can't work here: a section taller than ~5.5x the viewport can
    // never occupy 18% of it, so it would never reveal and would sit at
    // opacity 0 forever. That is exactly what hid the app catalog on phones
    // — 86 tiles collapse to one column at 390px, making the section
    // 4,700px against an 844px viewport (17.9%). Trigger on the element's
    // top crossing 85% of the viewport instead, which is height-independent.
  }, { threshold: 0, rootMargin: '0px 0px -15% 0px' });
  document.querySelectorAll('.m-section, .m-transition').forEach(function (el) { io.observe(el); });

  // Language card says hello in five languages
  var hello = document.querySelector('.hello');
  if (hello) {
    var his = ['— Hello', '— ¡Hola!', '— 你好', '— こんにちは', '— 안녕하세요'];
    var i = 0;
    setInterval(function () {
      hello.style.opacity = 0;
      setTimeout(function () {
        i = (i + 1) % his.length;
        hello.textContent = his[i];
        hello.style.opacity = 1;
      }, 250);
    }, 2200);
  }

  // App-icon confetti burst (reuses the hero rain icons)
  var iconSrcs = Array.prototype.slice.call(document.querySelectorAll('.rain img')).map(function (im) { return im.src; });
  function burst(x, y, n) {
    if (!iconSrcs.length) return;
    for (var k = 0; k < n; k++) {
      var img = document.createElement('img');
      img.src = iconSrcs[Math.floor(Math.random() * iconSrcs.length)];
      img.className = 'burst';
      img.style.left = (x - 17) + 'px';
      img.style.top = (y - 17) + 'px';
      document.body.appendChild(img);
      var ang = Math.random() * Math.PI * 2;
      var dist = 70 + Math.random() * 130;
      var dx = Math.cos(ang) * dist, dy = Math.sin(ang) * dist - 60;
      img.animate([
        { transform: 'translate(0,0) scale(.4) rotate(0deg)', opacity: 1 },
        { transform: 'translate(' + dx + 'px,' + (dy + 160) + 'px) scale(1) rotate(' + ((Math.random() - 0.5) * 540) + 'deg)', opacity: 0 }
      ], { duration: 900 + Math.random() * 500, easing: 'cubic-bezier(.2,.6,.3,1)' }).onfinish = function () { this.effect.target.remove(); }.bind ? function (ev) { ev.target.effect.target.remove(); } : null;
      (function (el) { setTimeout(function () { el.remove(); }, 1600); })(img);
    }
  }
  // click an eyebrow (or the headline period) → confetti
  document.querySelectorAll('.m-eyebrow, .m-h2').forEach(function (el) {
    el.style.cursor = 'default';
    el.addEventListener('click', function (e) { burst(e.clientX, e.clientY, 14); });
  });

  // Magnetic CTA + celebratory burst on click
  var cta = document.querySelector('#get .cta');
  if (cta) {
    var wrap = cta.parentElement;
    wrap.addEventListener('mousemove', function (e) {
      var r = cta.getBoundingClientRect();
      var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
      var d = Math.hypot(e.clientX - cx, e.clientY - cy);
      if (d < 160) {
        cta.style.transform = 'translate(' + (e.clientX - cx) * 0.18 + 'px,' + (e.clientY - cy) * 0.18 + 'px)';
      } else { cta.style.transform = ''; }
    });
    wrap.addEventListener('mouseleave', function () { cta.style.transform = ''; });
    cta.addEventListener('click', function (e) { burst(e.clientX, e.clientY, 22); });
  }

  // Tap a phone → pause/play with a spring pop
  document.querySelectorAll('.vid-live video').forEach(function (v) {
    v.style.cursor = 'pointer';
    v.addEventListener('click', function () {
      v.paused ? v.play() : v.pause();
      v.animate([{ transform: 'scale(1)' }, { transform: 'scale(.96)' }, { transform: 'scale(1)' }],
                { duration: 320, easing: 'cubic-bezier(.34,1.56,.64,1)' });
    });
  });
})();

// Make-it-yours live cards: the Avatar card cycles through cartoon faces
// (mixed styles); the Color card cycles the five real crown-pour colors
// (prd §204) — the same swatches the in-app picker offers, not a color well
// and not a photo (that picker was retired in-app 2026-07-06 and stays dead).
(function liveCards() {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var faces = Array.prototype.slice.call(document.querySelectorAll('.avatar-stack img'));
  var fill = document.querySelector('.pour-cycle .pour-fill');
  if (!faces.length && !fill) return;
  // Each pair is one of the five ThemeStore.bleeds, top stop to a darkened
  // stop — Blue, Teal, Violet, Magenta, Slate, in that order.
  var pours = ["linear-gradient(160deg, #1673e6, #0c3f7f)", "linear-gradient(160deg, #40c7c2, #236d6b)", "linear-gradient(160deg, #8c40c7, #4d236d)", "linear-gradient(160deg, #c74095, #6d2352)", "linear-gradient(160deg, #7b8a9e, #444c57)"];
  var fi = 0, pi = 0;
  setInterval(function () {
    if (faces.length) {
      faces[fi].classList.remove('on');
      fi = (fi + 1) % faces.length;
      faces[fi].classList.add('on');
    }
    if (fill) {
      pi = (pi + 1) % pours.length;
      fill.style.background = pours[pi];
    }
  }, 2400);
})();

// Data tile: the sync toggle flips itself and the phone lights up with it.
(function dataTile() {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var el = document.querySelector('.data-live');
  if (!el) return;
  setTimeout(function () {
    setInterval(function () { el.classList.toggle('on'); }, 2400);
  }, 1200);
})();

// "What you can do" switcher: four tabs, one stage. Panels are display:contents
// so the active one's children become grid items of the stage itself.
(function candoSwitcher() {
  var tabs = document.querySelectorAll('.sw-tab');
  if (!tabs.length) return;
  tabs.forEach(function (t) {
    t.addEventListener('click', function () {
      document.querySelectorAll('.sw-tab').forEach(function (x) { x.classList.remove('on', 'jiggle'); });
      document.querySelectorAll('.sw-panel').forEach(function (x) { x.classList.remove('on'); });
      t.classList.add('on');
      void t.offsetWidth; // restart the animation even if it's re-clicked
      t.classList.add('jiggle');
      var p = document.getElementById('p-' + t.dataset.p);
      if (p) p.classList.add('on');
    });
    t.addEventListener('animationend', function () { t.classList.remove('jiggle'); });
  });
})();


// ---------- Surprise & delight (2026-08-04) ----------------------------
// Each of these mirrors a delight the app itself ships; none run under
// Reduce Motion, and none move content anyone is reading.
(function delight() {
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // 1. Berry rain on the conversion tap — the app's good-refresh moment,
  //    played at the exact instant someone gets the app. The CTA opens in
  //    a new tab, so the shower is actually seen.
  var cta = document.getElementById('get-cta');
  if (cta && !still) {
    var BERRY = ['#2E63FF', '#855dcd', '#4C7DFF', '#3b8cf0', '#d9376e'];
    cta.addEventListener('click', function (e) {
      var r = cta.getBoundingClientRect();
      for (var i = 0; i < 12; i++) {
        var b = document.createElement('span');
        b.className = 'berry';
        b.style.background = BERRY[i % BERRY.length];
        b.style.left = (r.left + r.width * Math.random()) + 'px';
        b.style.top = (r.top + r.height / 2) + 'px';
        var drift = (Math.random() - 0.5) * 220;
        b.style.setProperty('--bx0', (drift * 0.25) + 'px');
        b.style.setProperty('--bx', drift + 'px');
        b.style.animationDelay = (Math.random() * 0.12) + 's';
        b.style.width = b.style.height = (9 + Math.random() * 7) + 'px';
        b.addEventListener('animationend', function () { this.remove(); });
        document.body.appendChild(b);
      }
    });
  }

  // 2. The hue pour follows the scroll: the top hairline takes the tint of
  //    the slab in view, and lets go outside the walkthrough.
  var pour = document.getElementById('pourline');
  var steps = document.querySelectorAll('.fstep');
  if (pour && steps.length && 'IntersectionObserver' in window) {
    var TINT = ['#2E63FF', '#855dcd', '#8a93a6', '#3fb950', '#64748b'];
    var stepIx = new Map();
    steps.forEach(function (el, i) { stepIx.set(el, i); });
    var pio = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) pour.style.backgroundColor = TINT[stepIx.get(en.target) % TINT.length];
        else if (stepIx.get(en.target) === steps.length - 1 && en.boundingClientRect.top < 0)
          pour.style.backgroundColor = 'transparent';
        else if (stepIx.get(en.target) === 0 && en.boundingClientRect.top > 0)
          pour.style.backgroundColor = 'transparent';
      });
    }, { rootMargin: '-40% 0px -40% 0px' });
    steps.forEach(function (el) { pio.observe(el); });
  }

  // 3. The tab-title whisper — the product's promise, in a background tab.
  var realTitle = document.title;
  document.addEventListener('visibilitychange', function () {
    document.title = document.hidden ? 'Your things are landing…' : realTitle;
  });

  // 4. The idle wink: after 20 quiet seconds with the catalog on screen,
  //    one random tile does a single coin-flip. Once per idle spell.
  if (!still) {
    var idleTimer = null, winked = false;
    var rearm = function () {
      winked = false;
      clearTimeout(idleTimer);
      idleTimer = setTimeout(function () {
        if (winked) return;
        var cat = document.getElementById('catalog');
        if (!cat) return;
        var rc = cat.getBoundingClientRect();
        if (rc.top > window.innerHeight || rc.bottom < 0) return;
        var tiles = cat.querySelectorAll('.mini-cell .ai');
        if (!tiles.length) return;
        var t = tiles[Math.floor(Math.random() * tiles.length)];
        t.classList.add('flip');
        t.addEventListener('animationend', function () { t.classList.remove('flip'); }, { once: true });
        winked = true;
      }, 20000);
    };
    ['scroll', 'mousemove', 'keydown', 'touchstart'].forEach(function (ev) {
      window.addEventListener(ev, rearm, { passive: true });
    });
    rearm();
  }
})();
