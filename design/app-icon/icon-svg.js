(function () {
  function col(mode, a) {
    return mode === 'tinted'
      ? 'rgba(255,255,255,' + a + ')'
      : 'rgba(10,132,255,' + a + ')';
  }
  function ground(mode) {
    return mode === 'light' ? '#FFFFFF' : '#000000';
  }
  // opaque tone: the hue pre-mixed toward the ground at level a — occludes, no compounding
  function solid(mode, a) {
    var fg = mode === 'tinted' ? [255, 255, 255] : [10, 132, 255];
    var bg = mode === 'light' ? [255, 255, 255] : [0, 0, 0];
    var c = fg.map(function (v, i) { return Math.round(v * a + bg[i] * (1 - a)); });
    return 'rgb(' + c.join(',') + ')';
  }

  function build(dir, mode) {
    var g = ground(mode);
    var b = function (a) { return col(mode, a); };
    var R = function (x, y, w, h, rx, a) {
      return '<rect x="' + x + '" y="' + y + '" width="' + w + '" height="' + h + '" rx="' + rx + '" fill="' + b(a) + '"/>';
    };
    var C = function (cx, cy, r, a) {
      return '<circle cx="' + cx + '" cy="' + cy + '" r="' + r + '" fill="' + b(a) + '"/>';
    };
    var body = '';

    switch (dir) {
      // 1 — berry as vessel: drupelet cluster, one rounded shape, opacity = magnitude
      case '1':
      case '1R':
      case '1A':
      case '1B':
      case '1C': {
        // positions: center first (drawn at back), then ring TL,TR,R,BR,BL,L
        var pts = [[512, 548], [426, 388], [598, 388], [684, 548], [598, 708], [426, 708], [340, 548]];
        var ops = {
          '1':  [0.62, 1.0, 0.5, 0.4, 0.3, 0.72, 0.85],
          '1R': [0.62, 1.0, 0.5, 0.4, 0.3, 0.72, 0.85],
          '1A': [1.0, 0.55, 0.4, 0.3, 0.22, 0.34, 0.46],   // core: brightest at center, graded ring
          '1B': [0.45, 1.0, 0.6, 0.32, 0.2, 0.32, 0.6],    // falloff: light enters top-left
          '1C': [0.5, 1.0, 0.85, 0.7, 0.55, 0.4, 0.28]     // spiral: steps clockwise around the ring
        }[dir];
        var r1 = dir === '1' ? 100 : 108;
        body = pts.map(function (p, i) { return C(p[0], p[1], r1, ops[i]); }).join('');
        break;
      }

      // 1D — falloff, opaque: solid pre-mixed tones, front drupelets occlude back ones
      case '1D': {
        var pts2 = [[512, 548], [426, 388], [598, 388], [684, 548], [598, 708], [426, 708], [340, 548]];
        var ops2 = [0.45, 1.0, 0.6, 0.32, 0.2, 0.32, 0.6];
        var berry = pts2.map(function (p, i) { return { p: p, a: ops2[i] }; })
          .sort(function (x, y) { return x.a - y.a; });
        body = berry.map(function (d) {
          return '<circle cx="' + d.p[0] + '" cy="' + d.p[1] + '" r="108" fill="' + solid(mode, d.a) + '"/>';
        }).join('');
        break;
      }

      // 2 — C cut as a pocket: the counter reads as an opening that holds
      case '2': {
        body = '<g transform="rotate(-55 512 512)"><circle cx="512" cy="512" r="265" fill="none" stroke="' + b(1) + '" stroke-width="150" stroke-linecap="round" stroke-dasharray="1341 324"/></g>';
        body += C(474, 486, 50, 0.55) + C(566, 522, 42, 0.4) + C(500, 602, 34, 0.28);
        break;
      }

      // 3 — treemap: rectangles of one hue at opacities, the product's magnitude language
      case '3': {
        body =
          R(140, 140, 430, 744, 0, 1.0) +
          R(588, 140, 139, 300, 0, 0.66) +
          R(745, 140, 139, 300, 0, 0.5) +
          R(588, 458, 296, 190, 0, 0.38) +
          R(588, 666, 139, 218, 0, 0.3) +
          R(745, 666, 139, 218, 0, 0.22);
        break;
      }
      case '3R': {
        body =
          R(140, 140, 400, 744, 0, 1.0) +
          R(558, 140, 155, 354, 0, 0.66) +
          R(729, 140, 155, 354, 0, 0.48) +
          R(558, 512, 155, 372, 0, 0.36) +
          R(729, 512, 155, 372, 0, 0.24);
        break;
      }

      // 3B — treemap idea in bento geometry: same partition, rounded cells
      case '3B': {
        body =
          R(140, 140, 400, 744, 44, 1.0) +
          R(558, 140, 155, 354, 44, 0.66) +
          R(729, 140, 155, 354, 44, 0.48) +
          R(558, 512, 155, 372, 44, 0.36) +
          R(729, 512, 155, 372, 44, 0.24);
        break;
      }

      // 4 — door ajar: the place things go, four strokes or fewer
      case '4': {
        body = '<rect x="150" y="150" width="724" height="724" rx="112" fill="none" stroke="' + b(0.9) + '" stroke-width="52"/>';
        body += '<g transform="rotate(-20 726 512)"><rect x="430" y="256" width="296" height="512" rx="18" fill="' + b(0.5) + '"/><circle cx="470" cy="512" r="26" fill="' + b(1) + '"/></g>';
        break;
      }

      // 5 — bento abstraction: the Home grid reduced to its silhouette
      case '5': {
        body =
          R(140, 140, 360, 744, 48, 1.0) +
          R(530, 140, 354, 354, 48, 0.6) +
          R(530, 524, 162, 360, 48, 0.42) +
          R(722, 524, 162, 360, 48, 0.28);
        break;
      }

      // 6 — berry that is a period: the mark as the end of the search
      case '6': {
        body = C(250, 540, 40, 0.3) + C(362, 540, 50, 0.48) + C(492, 540, 62, 0.66) + C(692, 566, 152, 1.0);
        break;
      }

      // 7 — nested cups: things caught and held (cache / catch)
      case '7': {
        var cup = function (r, sw, a) {
          return '<path d="M ' + (512 - r) + ' 452 A ' + r + ' ' + r + ' 0 0 0 ' + (512 + r) + ' 452" fill="none" stroke="' + b(a) + '" stroke-width="' + sw + '" stroke-linecap="round"/>';
        };
        body = cup(300, 74, 0.4) + cup(205, 74, 0.66) + cup(110, 74, 1.0);
        break;
      }

      // 8 — landing slot: many things drop into one place
      case '8': {
        body = R(232, 568, 560, 134, 67, 0.5) + C(512, 344, 108, 1.0) + C(512, 150, 58, 0.4);
        break;
      }
    }

    return '<svg viewBox="0 0 1024 1024" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" xmlns="http://www.w3.org/2000/svg">' +
      '<rect width="1024" height="1024" fill="' + g + '"/>' + body + '</svg>';
  }

  if (typeof window !== 'undefined') window.CasberiIconSVG = build;
  if (typeof module !== 'undefined' && module.exports) module.exports = build;
})();
