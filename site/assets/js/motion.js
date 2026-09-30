// One-shot reveals: a [data-reveal] block gets .is-inview the first time it is
// well inside the viewport, and site/assets/css/motion.css animates it from
// there. The resting state of every animation is the static page, so a
// visitor without this script, or with reduced motion, sees the same page.
(function () {
  var root = document.documentElement;
  if (!root.classList.contains('js-motion')) return;
  var observer = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      entry.target.classList.add('is-inview');
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.35 });
  document.querySelectorAll('[data-reveal]').forEach(function (el) { observer.observe(el); });
})();
