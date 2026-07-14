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
        // conservation of mass: the berry grows with every app it drinks
        target.style.transform = 'scale(' + (1 + 0.10 * done / n).toFixed(3) + ')';
        if (done % 4 === 0 && done < n) {
          target.animate(
            [{ transform: 'scale(1)' }, { transform: 'scale(1.045)' }, { transform: 'scale(1)' }],
            { duration: 200, easing: 'ease-out', composite: 'add' });
        }
        if (done === n) finale();
      };
    });
  }

  // Act 3 — payoff. The berry settles, then STREAMS: feed rows materialize
  // above it like generated UI, each led by one of the apps it just drank —
  // scattered apps in, one feed out. The streamed feed IS the end state.
  function finale() {
    setTimeout(function () {
      // the energy flows out: the berry springs back to size…
      target.style.transform = 'scale(1)';
      target.animate(
        [{ transform: 'scale(1.05)' }, { transform: 'scale(.96)' }, { transform: 'scale(1)' }],
        { duration: 480, easing: 'cubic-bezier(.34,1.56,.64,1)', composite: 'add' });
      // …and becomes a feed, streaming into the space the rain left behind
      rain.style.position = 'relative';
      var panel = document.createElement('div');
      panel.className = 'streamfeed';
      rain.appendChild(panel);
      var srcs = Array.prototype.slice.call(rain.querySelectorAll('img'))
        .map(function (im) { return im.src; });
      // a calm notification-style stack: three large cards, one column,
      // perfectly aligned — dealt out of the berry
      var picks = [srcs[2], srcs[9], srcs[17]].filter(Boolean);
      var widths = [[52, 30], [40, 22], [46, 26]];
      var rows = picks.map(function (src, k) {
        var row = document.createElement('div');
        row.className = 'streamrow';
        row.innerHTML = '<img src="' + src + '" alt="">' +
          '<span class="slines"><span class="sbar" style="width:0"></span>' +
          '<span class="sbar thin" style="width:0"></span></span>';
        panel.appendChild(row);
        return row;
      });
      var tRect = target.getBoundingClientRect();
      var tcx = tRect.left + tRect.width / 2, tcy = tRect.top + tRect.height / 2;
      function dealFrom(row) {
        var b = row.getBoundingClientRect();
        var dx = tcx - (b.left + b.width / 2), dy = tcy - (b.top + b.height / 2);
        row.style.transform = 'translate(' + dx + 'px,' + dy + 'px) scale(.3)';
      }
      function launch(row, k) {
        row.classList.add('in');
        row.style.transform = '';
        var bars = row.querySelectorAll('.sbar');
        setTimeout(function () { bars[0].style.width = widths[k % widths.length][0] + '%'; }, 180);
        setTimeout(function () { bars[1].style.width = widths[k % widths.length][1] + '%'; }, 340);
      }
      rows.forEach(dealFrom);
      rows.forEach(function (row, k) {
        setTimeout(function () { launch(row, k); }, 170 * k);
      });
      if (em) setTimeout(function () { em.classList.add('lit'); }, 170 * rows.length + 400);
      // one late arrival — things keep landing (once, then calm)
      setTimeout(function () {
        if (!panel.parentElement) return;
        var late = document.createElement('div');
        late.className = 'streamrow';
        late.innerHTML = '<img src="' + (srcs[25] || srcs[0]) + '" alt="">' +
          '<span class="slines"><span class="sbar" style="width:0"></span>' +
          '<span class="sbar thin" style="width:0"></span></span>';
        panel.appendChild(late);
        dealFrom(late);
        void late.offsetWidth;
        launch(late, 3);
      }, 170 * rows.length + 2300);
      setTimeout(function () { state = 'rested'; }, 170 * rows.length + 800);
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
  }, { threshold: 0.18 });
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
// (mixed styles), the Background card cycles the app's banner colors and
// lands on a photo — the two settings, demonstrating themselves.
(function liveCards() {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  var faces = Array.prototype.slice.call(document.querySelectorAll('.avatar-stack img'));
  var fill = document.querySelector('.bg-cycle .bg-fill');
  var photo = document.querySelector('.bg-cycle .bg-photo');
  if (!faces.length && !fill) return;
  var grads = ["linear-gradient(160deg, #55279c, #31165a)", "linear-gradient(160deg, #9e1b4a, #5b102b)", "linear-gradient(160deg, #9e241d, #5b1511)", "linear-gradient(160deg, #9e4b00, #5b2b00)", "linear-gradient(160deg, #006e76, #004044)", "linear-gradient(160deg, #0e722d, #08421a)"];
  var fi = 0, bi = 0;
  setInterval(function () {
    if (faces.length) {
      faces[fi].classList.remove('on');
      fi = (fi + 1) % faces.length;
      faces[fi].classList.add('on');
    }
    if (fill) {
      bi = (bi + 1) % (grads.length + 1);
      if (bi === grads.length) { photo.classList.add('on'); }
      else { photo.classList.remove('on'); fill.style.background = grads[bi]; }
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
