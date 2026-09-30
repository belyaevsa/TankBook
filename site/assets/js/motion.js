// One-shot reveals, served from the site's own origin: the nginx policy is
// script-src 'self', which blocks any inline script. A [data-reveal] block gets
// .is-inview the first time it is well inside the viewport, and
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
  }, { threshold: 0.35 });
  pending.forEach(function (el) { observer.observe(el); });
})();
