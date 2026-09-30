// One-shot reveals, served from the site's own origin: the nginx policy is
// script-src 'self', which blocks any inline script. A [data-reveal] block gets
// .is-inview the first time its top is well inside the viewport, and
// site/assets/css/motion.css animates it from there. The resting state of every
// animation is the static page:
// - without this script, or with reduced motion, `js-motion` is never set and
//   no start state applies;
// - a block already on screen when the script runs loses data-reveal and stays
//   as it is, so nothing visible is hidden and replayed.
(function () {
  if (!('IntersectionObserver' in window) || !window.matchMedia ||
      !window.matchMedia('(prefers-reduced-motion: no-preference)').matches) return;
  var blocks = Array.prototype.slice.call(document.querySelectorAll('[data-reveal]'));
  var pending = blocks.filter(function (el) {
    var box = el.getBoundingClientRect();
    if (box.top < window.innerHeight && box.bottom > 0) { el.removeAttribute('data-reveal'); return false; }
    return true;
  });
  document.documentElement.classList.add('js-motion');
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-inview');
      observer.unobserve(entry.target);
    });
  // Fires when a block's top passes 80 % of the viewport height - not a share of
  // the block, which a tall block (the ways-in cards stacked on a phone) never
  // reaches, leaving it hidden.
  }, { threshold: 0, rootMargin: '0px 0px -20% 0px' });
  pending.forEach(function (el) { observer.observe(el); });

  // Screen recordings (layouts/_partials/video.html): each plays once when half
  // in view, stops on its last frame and offers a replay. Without this script,
  // or with reduced motion, the poster - the same last frame - stays.
  var clips = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      clips.unobserve(entry.target);
      entry.target.play().catch(function () {});
    });
  }, { threshold: 0.5 });
  document.querySelectorAll('video[data-play-once]').forEach(function (video) {
    var replay = video.parentNode.querySelector('.clip__replay');
    video.addEventListener('ended', function () { if (replay) replay.hidden = false; });
    if (replay) replay.addEventListener('click', function () {
      replay.hidden = true; video.currentTime = 0; video.play().catch(function () {});
    });
    clips.observe(video);
  });
})();
