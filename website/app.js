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
  if (!rain || !target) return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  var icons = Array.prototype.slice.call(rain.children);
  var FLY = 520;       // one icon's flight into the tile
  var STAGGER = 40;
  var inFlight = false;

  function absorb() {
    if (inFlight) return;
    inFlight = true;
    var t = target.getBoundingClientRect();
    icons.forEach(function (el, i) {
      var r = el.getBoundingClientRect();
      var dx = (t.left + t.width / 2) - (r.left + r.width / 2);
      var dy = (t.top + t.height / 2) - (r.top + r.height / 2);
      el.animate(
        [
          { opacity: 1 },
          { transform: 'translate(' + dx + 'px,' + dy + 'px) scale(.1)', opacity: 0 }
        ],
        { duration: FLY, delay: i * STAGGER, easing: 'cubic-bezier(.5,0,.8,.4)', fill: 'forwards' }
      );
    });
    var total = icons.length * STAGGER + FLY;
    target.animate(
      [{ transform: 'scale(1)' }, { transform: 'scale(1.14)' }, { transform: 'scale(1)' }],
      { duration: 460, delay: Math.max(0, total - 260), easing: 'ease-out' }
    );
    setTimeout(rerain, total + 500);
  }

  function rerain() {
    icons.forEach(function (el, i) {
      el.getAnimations().forEach(function (a) { a.cancel(); });
      el.style.animation = 'none';
      void el.offsetWidth;               // reflow so the CSS animation restarts
      el.style.animation = '';
      el.style.animationDelay = (0.05 + i * 0.04) + 's';
    });
    // rest — no loop; the tile replays it on tap
    setTimeout(function () { inFlight = false; }, icons.length * 40 + 1000);
  }

  target.style.cursor = 'pointer';
  target.title = 'Tap to replay';
  target.addEventListener('click', absorb);

  setTimeout(absorb, 4200);   // play the story once after the first rain
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
