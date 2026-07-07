// Casberi site behavior — two things only:
// 1. Hero loop: the app icons rain in (CSS), sit a beat, then fly INTO the
//    Casberi tile and vanish; the tile pulses as it takes them; then the
//    rain falls again. The pitch, acted out, forever.
// 2. Scroll reveal: walkthrough sections fade up the first time they enter
//    the viewport. Content is fully visible without JS.

(function heroLoop() {
  var rain = document.querySelector('.rain');
  var target = document.querySelector('.rain-target .ai-casberi');
  if (!rain || !target) return;
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  var icons = Array.prototype.slice.call(rain.children);
  var SIT = 4200;      // how long the landed row rests before absorbing
  var FLY = 520;       // one icon's flight into the tile
  var STAGGER = 45;

  function visibleIcons() {
    return icons.filter(function (el) {
      return getComputedStyle(el).display !== 'none';
    });
  }

  function absorb() {
    var vis = visibleIcons();
    var t = target.getBoundingClientRect();
    vis.forEach(function (el, i) {
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
    var total = vis.length * STAGGER + FLY;
    target.animate(
      [{ transform: 'scale(1)' }, { transform: 'scale(1.14)' }, { transform: 'scale(1)' }],
      { duration: 460, delay: Math.max(0, total - 260), easing: 'ease-out' }
    );
    setTimeout(rerain, total + 600);
  }

  function rerain() {
    icons.forEach(function (el, i) {
      el.getAnimations().forEach(function (a) { a.cancel(); });
      el.style.animation = 'none';
      void el.offsetWidth;               // reflow so the CSS animation restarts
      el.style.animation = '';
      el.style.animationDelay = (0.05 + i * 0.08) + 's';
    });
    setTimeout(absorb, SIT);
  }

  setTimeout(absorb, SIT);
})();

(function scrollReveal() {
  if (!('IntersectionObserver' in window)) return;
  var els = document.querySelectorAll('.step-copy, .step-mock, .store-sec, .catalog-head, .final-cta');
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
