// Yandex.Metrika's loader, as a file: the site's CSP blocks inline scripts.
// Built by layouts/_partials/head/analytics.html with the counter id filled in.
// tag.js itself comes from mc.yandex.ru, which the CSP must also allow for the
// counter to run - see docs/SITE.md -> "Motion" and the Metrika note there.
(function (m, e, t, r, i, k, a) {
  m[i] = m[i] || function () { (m[i].a = m[i].a || []).push(arguments); };
  m[i].l = 1 * new Date();
  for (var j = 0; j < document.scripts.length; j++) { if (document.scripts[j].src === r) { return; } }
  k = e.createElement(t), a = e.getElementsByTagName(t)[0], k.async = 1, k.src = r, a.parentNode.insertBefore(k, a);
})(window, document, 'script', 'https://mc.yandex.ru/metrika/tag.js?id={{ .id }}', 'ym');
ym({{ .id }}, 'init', { ssr: true, webvisor: true, clickmap: true, ecommerce: 'dataLayer', referrer: document.referrer, url: location.href, accurateTrackBounce: true, trackLinks: true });
