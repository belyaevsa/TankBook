import Foundation

/// The pump class of `PostSweepCorpusAdditions`, kept in its own file so the
/// declaration list stays within the type-body limit as the corpus grows.
extension PostSweepCorpusAdditions {
    static let pump: Set<String> = [
        // 2026-09-09: the owner's own fills, three of them the matched
        // halves of receipt-053/054/055. Declared, not swept.
        "pump-074-gpn-tver-95-ru.jpg",
        "pump-075-gilbarco-circlek-ee-95.jpg",
        "pump-076-gilbarco-circlek-ee-preset-150.jpg",
        "pump-077-gilbarco-ee-2054.jpg",
        // 2026-09-10: five stale Gilbarco reads from one Circle K Peetri
        // forecourt (pump-082 is cropped so tightly that no unit label is
        // in frame) and the Tokheim half of receipt-060. Declared, not swept.
        "pump-078-gilbarco-circlek-peetri-pump7-3143l-ee.jpg",
        "pump-079-gilbarco-circlek-peetri-6900l-ee.jpg",
        "pump-080-gilbarco-circlek-peetri-1039l-ee.jpg",
        "pump-081-gilbarco-circlek-peetri-pump3-2496l-ee.jpg",
        "pump-082-gilbarco-circlek-peetri-1315l-ee.jpg",
        "pump-083-tokheim-gazpromneft-azs12089-truncated-total-pair-ru.jpeg",
        "pump-018-gilbarco-tatneft-tver-98-ru.jpeg",
        "pump-019-gilbarco-circlek-sikupilli-pump8-ee.jpg",
        "pump-020-gilbarco-circlek-sikupilli-pump7-ee.jpg",
        "pump-021-wayne-circlek-sun-glare-ee.jpg",
        "pump-022-wayne-circlek-pump1-glare-ee.jpg",
        "pump-023-wayne-circlek-glare-ee.jpg",
        // 2026-08-28: five Estonian additions (Neste Wayne x2, Circle K
        // Gilbarco x3). Declared, not swept: the A/B result files are
        // frozen at their pinned numbers and re-running the arms would
        // rebaseline P4.12/P4.13, which is a separate decision.
        "pump-024-wayne-neste-ee-three-grade-prices.jpg",
        "pump-025-wayne-neste-ee-glare-obscured-total.jpg",
        "pump-026-gilbarco-circlek-ee-comma-decimal.jpg",
        "pump-027-gilbarco-circlek-ee-comma-glare.jpg",
        "pump-028-gilbarco-circlek-ee-comma-decimal-b.jpg",
        "pump-029-dresser-wayne-gpn-okulovka-ru-glare-total.jpg",
        // 2026-08-30: the corpus's first TOKHEIM, and the matched half
        // of receipt-041. Declared, not swept.
        "pump-030-tokheim-zolotaya-seredina-tver-ru-comma.jpg",
        // 2026-08-31: eight Estonian Circle K displays - two Gilbarco and
        // six Dresser Wayne, including the matched half of receipt-042.
        // Declared, not swept.
        "pump-031-gilbarco-circlek-ee-discount-mismatch.jpg",
        "pump-032-gilbarco-circlek-ee-clean.jpg",
        "pump-033-dresser-wayne-circlek-ee-fourprice-95.jpg",
        "pump-034-dresser-wayne-circlek-tallinn-ee-db0-pair.jpg",
        "pump-035-dresser-wayne-circlek-ee-rain-pump8.jpg",
        "pump-036-dresser-wayne-circlek-ee-pump4-95.jpg",
        "pump-037-dresser-wayne-circlek-ee-pump3-diesel.jpg",
        "pump-038-dresser-wayne-circlek-ee-reflection-95.jpg",
        // 2026-09-01: five more Circle K Estonia displays. pump-042 is the
        // corpus's first PRESET-AMOUNT fill (a round 20.00 total, the
        // volume derived), and pump-041's total is destroyed by sun glare -
        // both leave a cell EMPTY rather than guess. Declared, not swept.
        "pump-039-gilbarco-circlek-ee-1839-clean.jpg",
        "pump-040-gilbarco-circlek-ee-pump4-wide.jpg",
        "pump-041-dresser-wayne-circlek-ee-glare-total.jpg",
        "pump-042-dresser-wayne-circlek-ee-preset-20eur.jpg",
        "pump-043-dresser-wayne-circlek-ee-pump8-95.jpg",
        // 2026-09-03: thirteen more. pump-044 is a Roснефть display whose
        // price is truncated to one decimal where its paired receipt prints
        // two. pump-045..pump-056 are one Circle K forecourt shot across
        // BOTH vendors - Gilbarco with comma decimals, Wayne with dots -
        // which is why the separator is a per-pump property, not a
        // per-locale one. Five Wayne displays charge a price that is not
        // any of the four on the board, and two lose their total to glare;
        // all of those leave a cell EMPTY rather than guess. Declared, not
        // swept.
        "pump-044-rn-tver-chkalovskaya-95-comma-truncated-price-ru.jpeg",
        "pump-045-gilbarco-circlek-ee-1799-zeropad.jpg",
        "pump-046-gilbarco-circlek-ee-pump7-95-badge.jpg",
        "pump-047-gilbarco-circlek-ee-pump8-outdoor.jpg",
        "pump-048-gilbarco-circlek-ee-1889-near-preset.jpg",
        "pump-049-gilbarco-circlek-ee-faint-lcd-small-fill.jpg",
        "pump-050-gilbarco-circlek-ee-1929.jpg",
        "pump-051-wayne-circlek-ee-fourprice-none-matches.jpg",
        "pump-052-wayne-circlek-ee-glare-total-lost.jpg",
        "pump-053-wayne-circlek-ee-pump1-glare-total-digit.jpg",
        "pump-054-wayne-circlek-jarvevana-pump7-diesel-flare.jpg",
        "pump-055-wayne-circlek-ee-liitrid-variant.jpg",
        "pump-056-wayne-circlek-ee-preset-72eur.jpg",
        // 2026-09-04: eight more Circle K Sikupilli displays, four
        // Gilbarco and four Dresser Wayne, including the matched half of
        // receipt-046. pump-061 charges a price on no board price of its
        // own display, and pump-063's price display is physically covered
        // by a dead insect - a NEW occlusion class, an object on the glass
        // rather than glare or dirt. Declared, not swept.
        "pump-057-gilbarco-circlek-sikupilli-pump5-db0-pair.jpg",
        "pump-058-gilbarco-circlek-ee-dirty-lcd-1969.jpg",
        "pump-059-gilbarco-circlek-ee-pump3-1899.jpg",
        "pump-060-gilbarco-circlek-ee-1894.jpg",
        "pump-061-wayne-circlek-ee-discount-below-board.jpg",
        "pump-062-wayne-circlek-ee-pump8-1894.jpg",
        "pump-063-wayne-circlek-ee-insect-on-price-display.jpg",
        "pump-064-wayne-circlek-ee-4645l-1834.jpg",
        // 2026-09-04: the matched halves of receipt-047 and receipt-048.
        // pump-065's Tokheim truncates its total to one decimal (3765,7 vs
        // the paper's 3765.65) where pump-066 agrees to the cent - so total
        // precision is a property of the PUMP, not the country. Declared,
        // not swept.
        "pump-065-tokheim-gazpromneft-edrovo-truncated-total-pair-ru.jpeg",
        "pump-066-rn-tver-budovo-95-exact-total-pair-ru.jpeg",
        // 2026-09-07 (RV.114): six Circle K Tallinn displays from one
        // session - 067 and 068 are the pump halves of receipt-049 and
        // -050, the corpus's first matched pairs with truth on BOTH sides;
        // 069 is 90-degree rotated; 071 catches a litre digit mid-segment;
        // 072 is a four-grade Wayne board whose displayed prices do NOT
        // include the transaction's (a loyalty discount). Declared, not
        // swept - the arms are frozen and RV.114 owns the scoring.
        "pump-067-circlek-jarvevana-95miles-4837l-glare-pair-ee.jpg",
        "pump-068-circlek-jarvevana-dmiles-7070l-pair-ee.jpg",
        "pump-069-circlek-gilbarco-2914l-rotated90-ee.jpg",
        "pump-070-circlek-gilbarco-3494l-ee.jpg",
        "pump-071-circlek-gilbarco-1898l-midsegment-ee.jpg",
        "pump-072-circlek-wayne-1001l-loyalty-price-off-board-ee.jpg",
        // 2026-09-07: a Wayne display whose SUMMA reads 2249.9 while the
        // receipt says 2249.92 - the truncated-total shape, with its paper
        // half at receipt-052. Declared, not swept.
        "pump-073-wayne-gazpromneft-tver-truncated-total-pair-ru.jpeg",
        // 2026-09-10: the Wayne half of receipt-061, and the only
        // Gazpromneft pair in the corpus whose display agrees with the
        // paper to the cent. Declared, not swept.
        "pump-084-dresser-wayne-gpn-okulovka-exact-total-pair-ru.jpeg",
        // 2026-09-11: two Tokheim displays paired with receipt-062/063,
        // seven Scheidt & Bachmann displays shot through glass with the
        // forecourt reflected in it (three of them one fill, three shots),
        // and two Circle K Gilbarco reads, one the display half of
        // receipt-064. Declared, not swept.
        "pump-085-tokheim-rn-tver-chkalovskaya-3000l-pair-ru.jpeg",
        "pump-086-tokheim-rn-tver-chkalovskaya-1000l-pair-ru.jpeg",
        "pump-087-scheidt-bachmann-rn-3000l-6830-reflection-a-ru.jpeg",
        "pump-088-scheidt-bachmann-rn-3000l-6830-reflection-b-ru.jpeg",
        "pump-089-scheidt-bachmann-rn-1500l-6830-ru.jpeg",
        "pump-090-scheidt-bachmann-rn-3000l-6830-reflection-c-ru.jpeg",
        "pump-091-scheidt-bachmann-rn-2000l-7135-labels-cropped-ru.jpeg",
        "pump-092-scheidt-bachmann-rn-3000l-6385-ru.jpeg",
        "pump-093-scheidt-bachmann-rn-2000l-6385-faded-ru.jpeg",
        "pump-094-gilbarco-circlek-ee-4325l-1944.jpg",
        "pump-095-gilbarco-circlek-peetri-pump5-2307l-pair-ee.jpg",
        // 2026-09-13: the Tokheim display half of receipt-065, at a third
        // RN-Tver station. Declared, not swept.
        "pump-096-tokheim-rn-tver-tc252-2000l-pair-ru.jpeg",
        // 2026-09-13: four Circle K Estonia Dresser Wayne displays on the
        // same SUMMA/LIITRIT/HIND-1L face - three from the owner's set and
        // pump-100, the display half of receipt-066. Declared, not swept.
        "pump-097-dresser-wayne-circlek-ee-2285l-1899.jpg",
        "pump-098-dresser-wayne-circlek-ee-969l-2039.jpg",
        "pump-099-dresser-wayne-circlek-ee-pump1-1064l-1899.jpg",
        "pump-100-dresser-wayne-circlek-jarvevana-pump4-6404l-2024-pair-ee.jpg",
        // 2026-09-14: five Circle K Estonia Gilbarco displays. pump-104 is
        // the display half of receipt-067 and its price window is washed
        // out, so that cell is deliberately blank. Declared, not swept.
        "pump-101-gilbarco-circlek-ee-1765l-2034-closeup.jpg",
        "pump-102-gilbarco-circlek-ee-1022l-1954.jpg",
        "pump-103-gilbarco-circlek-ee-4858l-1954.jpg",
        "pump-104-gilbarco-circlek-sikupilli-pump1-2650l-price-washed-pair-ee.jpg",
        "pump-105-gilbarco-circlek-ee-2555l-1899.jpg",
        // 2026-09-18: five Telegram-routed Russian displays - two Wayne
        // SUMMA/LITRY faces that truncate the total to 0.1 RUB (110 is the
        // display half of receipt-071), a night-lit zero-padded Scheidt &
        // Bachmann face paired with receipt-068/069, a daylight Scheidt &
        // Bachmann with the photographer reflected, and the Tokheim half
        // of receipt-070 - plus four full-resolution Circle K Estonia
        // Gilbarco displays, 114 with sun glare across the price window.
        // Declared, not swept.
        "pump-106-wayne-gazpromneft-gdrive95-5100l-7031-truncated-total-ru.jpeg",
        "pump-107-scheidt-bachmann-rn-tver-azk15-3000l-6830-night-zero-padded-pair-ru.jpeg",
        "pump-108-scheidt-bachmann-rn-3249l-6830-reflection-ru.jpeg",
        "pump-109-tokheim-gazpromneft-edrovo-4800l-7105-pair-ru.jpeg",
        "pump-110-wayne-gazpromneft-gdrive95-4200l-7031-truncated-total-pair-ru.jpeg",
        "pump-111-gilbarco-circlek-ee-5046l-1999.jpg",
        "pump-112-gilbarco-circlek-ee-461l-2199.jpg",
        "pump-113-gilbarco-circlek-ee-522l-2014.jpg",
        "pump-114-gilbarco-circlek-ee-6987l-2074-price-glare.jpg",
        // 2026-09-19/20: the pump reader's intake (PU.29-PU.33) - two
        // Sikupilli pairs, then the third-party web stills that brought the
        // corpus its Veeder-Root keypad, Tokheim Quality, Tatsuno and
        // Pignone heads and eleven currencies, then four owner captures.
        // Declared, not swept - the A/B arms remain frozen.
        "pump-115-gilbarco-circlek-sikupilli-pump7-98miles-1517l-1979-pair-ee.jpg",
        "pump-116-gilbarco-circlek-sikupilli-pump8-98miles-2786l-1979-pair-ee.jpg",
        "pump-117-wayne-alexela-98-press-err-third-party-ee.jpg",
        "pump-118-wayne-circlek-98-glare-total-instagram-third-party-ee.jpg",
        "pump-119-wayne-circlek-95miles-1369-drive2-third-party-ee.jpg",
        "pump-120-wayne-circlek-four-prices-drive2-third-party-ee.jpg",
        "pump-121-wayne-neste-1422-drive2-third-party-ee.jpg",
        "pump-122-wayne-circlek-98milesplus-1419-drive2-third-party-ee.jpg",
        "pump-123-unknown-comma-1911-drive2-third-party-ru.jpg",
        "pump-124-unknown-zero-padded-comma-price-cut-drive2-third-party-ru.jpg",
        "pump-125-wayne-circlek-price-out-of-frame-drive2-third-party-ee.jpg",
        "pump-126-gilbarco-circlek-zero-padded-price-out-of-frame-drive2-third-party-ee.jpg",
        "pump-127-wayne-idle-zero-three-prices-lounaleht-third-party-ee.jpg",
        "pump-128-wayne-gazpromneft-idle-zero-five-prices-third-party-ru.jpg",
        "pump-129-wayne-circlek-98milesplus-1402-third-party-ee.jpg",
        "pump-130-wayne-1000-rub-six-cells-third-party-ru.jpg",
        "pump-131-wayne-circlek-forecourt-far-display-third-party-lt.jpg",
        "pump-132-wayne-circlek-1399-third-party-lt.jpg",
        "pump-133-wayne-circlek-total-cut-at-top-four-prices-third-party-ee.jpg",
        "pump-134-tokheim-kronur-5000-third-party-is.jpg",
        "pump-135-tokheim-manat-tiny-display-third-party-tm.jpg",
        "pump-136-wayne-kroner-717-third-party-no.jpg",
        "pump-137-wayne-pence-this-sale-third-party-gb.jpg",
        "pump-138-wayne-talvine-monochrome-no-price-third-party-ee.jpg",
        "pump-139-wayne-euro-1613-third-party-fr.jpg",
        "pump-140-wayne-circlek-1849-rounding-third-party-lt.jpg",
        "pump-141-wayne-kronor-957-price-cut-left-third-party-se.jpg",
        "pump-142-wayne-1600-not-closing-third-party-ru.jpg",
        "pump-143-wayne-3921-95-third-party-ru.jpg",
        "pump-144-wayne-alexela-98-same-fill-as-117-wider-third-party-ee.jpg",
        "pump-145-tokheim-pence-comma-stock-photo-third-party-gb.jpg",
        "pump-146-wayne-gazpromneft-1100-92-third-party-ru.jpg",
        "pump-147-wayne-eur-1494-third-party-ee.jpg",
        "pump-148-wayne-1634-95-third-party-ru.jpg",
        "pump-149-wayne-circlek-diesel-1272-third-party-ee.jpg",
        "pump-150-wayne-euroa-four-prices-glare-third-party-fi.jpg",
        "pump-151-gilbarco-circlek-zero-padded-2044-graphic-overlay-third-party-ee.jpg",
        "pump-152-wayne-305-third-party-ru.jpg",
        "pump-153-gilbarco-veeder-root-keypad-three-prices-third-party-ru.jpg",
        "pump-154-gilbarco-veeder-root-keypad-1494-third-party-ru.jpg",
        "pump-155-gilbarco-veeder-root-keypad-four-prices-third-party-ru.jpg",
        "pump-156-gilbarco-veeder-root-keypad-backlit-three-prices-third-party-ru.jpg",
        "pump-157-gilbarco-veeder-root-ladder-cut-left-third-party-ru.jpg",
        "pump-158-gilbarco-veeder-root-wet-9900-one-decimal-third-party-ru.jpg",
        "pump-159-gilbarco-veeder-root-preset-20-litres-third-party-ru.jpg",
        "pump-160-gilbarco-veeder-root-zero-padded-not-closing-third-party-ru.jpg",
        "pump-161-gilbarco-veeder-root-tv-still-800px-third-party-ru.jpg",
        "pump-162-gilbarco-veeder-root-backlit-four-prices-666-third-party-ru.jpg",
        "pump-163-wayne-keypad-1997-92-third-party-ru.jpg",
        "pump-164-wayne-keypad-diesel-glare-total-third-party-ru.jpg",
        "pump-165-gilbarco-veeder-root-four-prices-680px-third-party-ru.jpg",
        "pump-166-gilbarco-veeder-root-angled-watermark-third-party-ru.jpg",
        "pump-167-gilbarco-veeder-root-shell-zero-padded-third-party-ru.jpg",
        "pump-168-gilbarco-veeder-root-lukoil-zero-padded-four-prices-third-party-ru.jpg",
        "pump-169-gilbarco-veeder-root-total-not-closing-video-still-third-party-ru.jpg",
        "pump-170-gilbarco-veeder-root-teboil-zero-padded-preset-11-litres-third-party-ru.jpg",
        "pump-171-gilbarco-veeder-root-night-two-prices-third-party-ru.jpg",
        "pump-172-gilbarco-veeder-root-lukoil-point-decimals-576px-third-party-ru.jpg",
        "pump-173-gilbarco-veeder-root-cents-per-litre-tilted-third-party-au.jpg",
        "pump-174-wayne-keypad-lukoil-ekto-diesel-680px-third-party-ru.jpg",
        "pump-175-gilbarco-veeder-root-zero-padded-189-third-party-ru.jpg",
        "pump-176-gilbarco-veeder-root-5388-diesel-third-party-ru.jpg",
        "pump-177-gilbarco-veeder-root-leva-640px-third-party-bg.jpg",
        "pump-178-gilbarco-veeder-root-forecourt-far-670px-third-party-ru.jpg",
        "pump-179-gilbarco-veeder-root-lukoil-winter-four-prices-third-party-ru.jpg",
        "pump-180-gilbarco-veeder-root-cents-per-litre-portrait-third-party-au.jpg",
        "pump-181-gilbarco-veeder-root-preset-20-litres-577px-third-party-ru.jpg",
        "pump-182-wayne-pignone-belarus-rubles-third-party-by.jpg",
        "pump-183-gilbarco-veeder-root-through-car-window-third-party-ru.jpg",
        "pump-184-gilbarco-veeder-root-three-prices-1280x576-third-party-ru.jpg",
        "pump-185-gilbarco-veeder-root-cents-per-litre-four-grades-third-party-au.jpg",
        "pump-186-tatsuno-amber-led-night-third-party-ru.jpg",
        "pump-187-tatsuno-amber-led-night-preset-20-third-party-ru.jpg",
        "pump-188-wayne-pignone-preset-20-third-party-ru.jpg",
        "pump-189-gilbarco-veeder-root-point-decimals-preset-20-third-party-ru.jpg",
        "pump-190-tokheim-tenge-fog-third-party-kz.jpg",
        "pump-191-tokheim-preset-500-rub-one-decimal-third-party-ru.jpg",
        "pump-192-tokheim-3602-one-decimal-reflection-third-party-ru.jpg",
        "pump-193-tokheim-3686-one-decimal-reflection-third-party-ru.jpg",
        "pump-194-tokheim-4968-dusk-third-party-ru.jpg",
        "pump-195-tokheim-lukoil-night-481-third-party-ru.jpg",
        "pump-196-tokheim-lukoil-snow-night-1895-third-party-ru.jpg",
        "pump-197-tokheim-amber-backlight-lamp-glare-third-party-ru.jpg",
        "pump-198-tokheim-lukoil-426-reflection-third-party-ru.jpg",
        "pump-199-tokheim-1630-large-cells-third-party-ru.jpg",
        "pump-200-tokheim-preset-990-litres-cash-litres-keypad-third-party-ru.jpg",
        "pump-201-tokheim-belarus-night-third-party-by.jpg",
        "pump-202-tokheim-preset-1000-rub-one-decimal-night-third-party-ru.jpg",
        "pump-203-unknown-three-rows-photographer-reflection-third-party-ru.jpg",
        "pump-204-tokheim-bashneft-small-display-third-party-ru.jpg",
        "pump-205-tokheim-364-tilted-third-party-ru.jpg",
        "pump-206-tokheim-1499-one-decimal-blur-third-party-ru.jpg",
        "pump-207-dresser-wayne-summa-1136-third-party-ru.jpg",
        "pump-208-gilbarco-veeder-root-night-rain-price-dim-third-party-ru.jpg",
        "pump-209-wayne-pesos-three-decimal-litres-third-party-ph.jpg",
        "pump-210-wayne-pignone-gazpromneft-summa-1610-third-party-ru.jpg",
        "pump-211-wayne-reais-three-grades-600px-third-party-br.jpg",
        "pump-212-dresser-wayne-circlek-diesel-6300l-2069-ee.jpg",
        "pump-213-gilbarco-circlek-zero-padded-6300l-1789-ee.jpg",
        "pump-214-gilbarco-veederroot-6714l-5181-rubles-ru.jpg",
        "pump-215-gilbarco-veederroot-lukoil-zero-padded-1511l-5358-board-ru.jpg",
        "pump-216-gilbarco-veederroot-night-2000l-5210-ru.jpg",
        "pump-217-gilbarco-veederroot-cents-per-litre-e85-19689l-1409-au.jpg",
        // 2026-09-21: the owner's 2026-09-20/21 intake - Topaz, Wayne and
        // Gilbarco Veeder-Root heads, a Topaz service-mode negative (226).
        "pump-218-unknown-tkk-diesel-glare-6975-ru.jpg",
        "pump-219-gilbarco-veederroot-zero-padded-3000l-6616-ru.jpg",
        "pump-220-topaz-gdrive-gazpromneft-dusk-4590l-6561-ru.jpg",
        "pump-221-topaz-gazpromneft-postpay-3824l-5965-ru.jpg",
        "pump-222-topaz-gazpromneft-trucks-mid-count-1788l-6039-ru.jpg",
        "pump-223-gilbarco-gdrive-board-glare-5503l-5220-ru.jpg",
        "pump-224-topaz-gazprom-truck-71428l-4900-ru.jpg",
        "pump-225-topaz-gazpromneft-reflection-4901l-6922-ru.jpg",
        "pump-226-topaz-service-mode-no-fill-ru.jpg",
        "pump-227-topaz-gdrive-dusk-4682l-6900-third-party-ru.jpg",
        "pump-228-topaz-deko-321l-7800-ru.jpg",
        "pump-229-wayne-gazpromneft-board-price-4000l-4245-ru.jpg",
        "pump-230-topaz-gazpromneft-taxi-3617l-6537-ru.jpg",
        "pump-231-topaz-gdrive-video-frame-3707l-6959-third-party-ru.jpg",
        "pump-232-tokheim-gdrive-one-decimal-total-2046l-4775-ru.jpg",
        "pump-233-topaz-autumn-3349l-7570-ru.jpg",
        "pump-234-topaz-clip-frame-590l-6941-third-party-ru.jpg",
        "pump-235-wayne-gdrive-night-board-price-1475l-243-by.jpg",
        "pump-236-wayne-gazpromneft-night-snow-6500l-4625-ru.jpg",
        "pump-237-tokheim-omsk-2062l-4850-ru.jpg",
        "pump-238-gilbarco-veederroot-three-decimal-price-3970l-1809-fr.jpg",
        "pump-239-wayne-gdrive-board-price-854l-3515-ru.jpg",
        "pump-240-gilbarco-veederroot-lukoil-9000l-5215-ru.jpg",
        "pump-241-wayne-pignone-dm3-528l-469-pl.jpg",
        // 2026-09-21 (evening): the owner's Estonian sweep - Circle K Peetri
        // Gilbarco pumps 1-9, Wayne Neste/Circle K/Olerex boards, two idle
        // and one closed-text negative, a five-grade Circle K head.
        "pump-242-wayne-neste-2461-1313l-board-ee.jpg",
        "pump-243-wayne-neste-2461-1313l-board-second-angle-ee.jpg",
        "pump-244-wayne-neste-5225-2788l-board-reflection-ee.jpg",
        "pump-245-gilbarco-circlek-peetri-pump2-4419l-1919-ee.jpg",
        "pump-246-gilbarco-circlek-peetri-pump2-4419l-1919-second-angle-ee.jpg",
        "pump-247-gilbarco-circlek-peetri-pump1-3647l-1919-ee.jpg",
        "pump-248-gilbarco-circlek-peetri-pump3-2143l-2099-pair-ee.jpg",
        "pump-249-gilbarco-circlek-peetri-pump3-2143l-2099-pair-close-ee.jpg",
        "pump-250-gilbarco-circlek-peetri-pump7-3590l-2099-ee.jpg",
        "pump-251-gilbarco-circlek-peetri-pump7-3590l-2099-close-ee.jpg",
        "pump-252-gilbarco-circlek-peetri-pump8-3242l-2099-ee.jpg",
        "pump-253-gilbarco-circlek-peetri-pump5-98miles-1790l-1959-glare-pair-ee.jpg",
        "pump-254-gilbarco-circlek-peetri-pump9-adblue-375l-0959-ee.jpg",
        "pump-255-gilbarco-circlek-peetri-pump6-2001l-2099-ee.jpg",
        "pump-256-gilbarco-circlek-peetri-pump6-1520l-2099-off-by-a-cent-ee.jpg",
        "pump-257-gilbarco-circlek-peetri-pump7-2032l-price-glare-ee.jpg",
        "pump-258-gilbarco-circlek-peetri-pump4-3506l-1919-ee.jpg",
        "pump-259-gilbarco-circlek-peetri-pump8-6286l-2099-ee.jpg",
        "pump-260-wayne-circlek-pump5-1000l-board-ee.jpg",
        "pump-261-wayne-circlek-pump5-1000l-board-oblique-ee.jpg",
        "pump-262-wayne-circlek-pump2-1723l-board-ee.jpg",
        "pump-263-wayne-circlek-pump4-closed-text-negative-ee.jpg",
        "pump-264-wayne-circlek-pump4-2887l-board-ee.jpg",
        "pump-265-wayne-circlek-pump4-2887l-board-second-angle-ee.jpg",
        "pump-266-wayne-circlek-pump3-3629l-discounted-price-board-ee.jpg",
        "pump-267-wayne-circlek-pump1-glare-liters-board-ee.jpg",
        "pump-268-wayne-olerex-tankur3-idle-board-ee.jpg",
        "pump-269-wayne-olerex-tankur5-idle-board-ee.jpg",
        "pump-270-gilbarco-circlek-five-grade-3197l-1979-ee.jpg",
        "pump-271-gilbarco-circlek-five-grade-1125l-2232-ee.jpg",
        "pump-272-gilbarco-circlek-five-grade-pump4-4049l-2132-ee.jpg",
        "pump-273-gilbarco-circlek-five-grade-pump2-3546l-1919-ee.jpg",
        // 2026-09-21 (night): the owner's Neste night sweep.
        "pump-274-wayne-neste-night-3024-1513l-board-ee.jpg",
        "pump-275-wayne-neste-night-10337-5171l-board-ee.jpg",
        "pump-276-wayne-neste-night-8605-3913l-board-ee.jpg",
        "pump-277-gilbarco-circlek-peetri-night-pump2-1754l-1959-ee.jpg",
        "pump-278-gilbarco-circlek-peetri-night-pump4-3497l-1999-off-by-a-cent-pair-ee.jpg",
        "pump-279-gilbarco-circlek-peetri-night-pump3-800l-2059-pair-ee.jpg",
        "pump-280-gilbarco-circlek-night-pump11-323l-2184-ee.jpg",
        "pump-281-gilbarco-circlek-night-pump12-2349l-1949-ee.jpg",
        // 2026-09-22 and 2026-09-23 intakes (batches 8-10): Circle K, Wayne and
        // Gilbarco heads in EE/FR/DE/BE/GB/FI, and the rain set. Declared, not swept.
        "pump-282-gilbarco-circlek-sikupilli-1723l-1999-ee.jpg",
        "pump-283-gilbarco-circlek-sikupilli-1438l-2299-ee.jpg",
        "pump-284-gilbarco-circlek-sikupilli-glare-2003l-2169-ee.jpg",
        "pump-285-gilbarco-circlek-sikupilli-500l-2199-ee.jpg",
        "pump-286-gilbarco-circlek-sikupilli-pump7-4089l-2199-pair-ee.jpg",
        "pump-287-wayne-circlek-jarvevana-pump8-2991l-board-ee.jpg",
        "pump-288-wayne-circlek-jarvevana-liitrid-3414l-board-ee.jpg",
        "pump-289-wayne-circlek-jarvevana-liitrid-preset-60-2710l-board-ee.jpg",
        "pump-290-wayne-circlek-jarvevana-pump2-1479l-board-pair-ee.jpg",
        "pump-291-wayne-circlek-jarvevana-pump1-oblique-4181l-board-ee.jpg",
        "pump-292-gilbarco-circlek-pump5-4010l-2004-ee.jpg",
        "pump-293-gilbarco-circlek-pump5-4010l-2004-second-angle-ee.jpg",
        "pump-294-gilbarco-circlek-pump3-1901l-2079-ee.jpg",
        "pump-295-gilbarco-circlek-pump4-1360l-2209-ee.jpg",
        "pump-296-wayne-circlek-liitrid-5127l-board-ee.jpg",
        "pump-297-wayne-circlek-liitrid-glare-765l-board-ee.jpg",
        "pump-298-wayne-circlek-liitrid-6953l-board-ee.jpg",
        "pump-299-wayne-circlek-liitrid-2276l-board-ee.jpg",
        "pump-300-wayne-circlek-liitrid-1370l-board-ee.jpg",
        "pump-301-wayne-circlek-liitrid-idle-reflection-board-ee.jpg",
        "pump-302-wayne-circlek-liitrid-tilted-1384l-board-ee.jpg",
        "pump-303-unknown-lpg-3222-7877l-0409-fr.jpg",
        "pump-304-tokheim-casadei-prix-volume-reflection-22047-9152l-2409-fr.jpg",
        "pump-305-tokheim-prix-volume-tilted-15250-6078l-2509-fr.jpg",
        "pump-306-tokheim-twin-idle-betrag-abgabe-zeros-de.jpg",
        "pump-307-unknown-total-excellium-corrected-15c-board-19772-8475l-2333-be.jpg",
        "pump-308-gilbarco-uk-this-sale-preset-500-311l-1609-board-gb.jpg",
        "pump-309-gilbarco-uk-this-sale-preset-1600-1234l-1297-board-gb.jpg",
        "pump-310-gilbarco-uk-this-sale-oblique-14166-8696l-1629-board-gb.jpg",
        "pump-311-gilbarco-tesco-pump7-far-7383-5203l-1419-board-gb.jpg",
        "pump-312-gilbarco-uk-night-caption-7891-4112l-1919-board-gb.jpg",
        "pump-313-unknown-uk-blue-pump4-no-price-window-9639-5707l-1689-board-gb.jpg",
        "pump-314-gilbarco-uk-this-sale-15386-9274l-1659-board-gb.jpg",
        "pump-315-unknown-finland-euroa-litraa-reflection-1226-583l-2103-board-fi.jpg",
        "pump-316-gilbarco-uk-night-preset-4900-3632l-1349-board-gb.jpg",
        "pump-317-wayne-lafon-nozzles-3508-2340l-1499-fr.jpg",
        "pump-318-wayne-lafon-leclerc-louhans-cropped-8373-4363l-1919-fr.jpg",
        "pump-319-wayne-neste-11808-5639l-board-rain-ee.jpg",
        "pump-320-wayne-neste-11808-5639l-board-rain-tilted-second-angle-ee.jpg",
        "pump-321-wayne-neste-3848-2005l-board-rain-tilted-ee.jpg",
        "pump-322-wayne-neste-6503-3389l-board-rain-tilted-ee.jpg",
        "pump-323-wayne-neste-6503-3389l-board-rain-second-angle-ee.jpg",
        "pump-324-gilbarco-circlek-17401-8310l-2094-rain-ee.jpg",
        "pump-325-gilbarco-circlek-17401-8310l-2094-rain-second-angle-ee.jpg",
        "pump-326-gilbarco-circlek-2117-1011l-2094-rain-ee.jpg",
        "pump-327-gilbarco-circlek-6772-3234l-2094-rain-ee.jpg",
        "pump-328-wayne-neste-4736-2381l-board-rain-tilted-ee.jpg",
        // 2026-09-24, batch 11: Circle K at night, declared not swept.
        "pump-329-gilbarco-circlek-2020-951l-2124-night-tilted-ee.jpg",
        "pump-330-gilbarco-circlek-7645-3591l-2129-night-oblique-ee.jpg",
        "pump-331-gilbarco-circlek-3264-1533l-2129-night-ee.jpg",
        // 2026-09-24, batch 11b: Alexela, black LCDs and a CNG dead-segment price.
        "pump-332-unknown-alexela-black-lcd-idle-board-reflection-ee.jpg",
        "pump-333-unknown-alexela-cng-2106-1109kg-dead-segments-ee.jpg",
        "pump-334-unknown-alexela-black-lcd-idle-board-self-reflection-ee.jpg",
        "pump-335-unknown-alexela-black-lcd-idle-board-ee.jpg",
        // 2026-09-25: the Capture lab's first run, high1080 preset (a pair).
        "pump-336-gilbarco-circlek-sikupilli-pump8-3002-1400l-2144-high1080-pair-ee.jpg",
        // 2026-09-25, batch 12: a Terminal TFT screen, Neste boards, a Voltera LCD.
        "pump-337-tokheim-terminal-tft-screen-7280-3500l-2080-ee.jpg",
        "pump-338-wayne-neste-vesse-10339-5121l-board-ee.jpg",
        "pump-339-unknown-neste-black-lcd-pump3-2999-1531l-board-ee.jpg",
        "pump-340-unknown-neste-black-lcd-pump4-1961-1001l-board-ee.jpg",
        "pump-341-unknown-voltera-yellow-lcd-idle-1219-ee.jpg",
        // 2026-09-26, batch 13: Circle K at night, Alexela black LCDs in the rain.
        "pump-342-gilbarco-circlek-11097-5469l-2029-night-high1080-ee.jpg",
        "pump-343-gilbarco-circlek-12038-5977l-2014-night-tilted-ee.jpg",
        "pump-344-unknown-alexela-black-lcd-idle-board-2059-rain-ee.jpg",
        "pump-345-unknown-alexela-black-lcd-idle-board-2059-night-wide-ee.jpg",
        // 2026-09-27, batch 14: Circle K Tammisaare Gilbarcos, Tokheim TFT screens at Olerex Peetri.
        "pump-346-gilbarco-circlek-4123-2017l-2044-pump1-ee.jpg",
        "pump-347-gilbarco-circlek-3800-2001l-pump6-price-glare-ee.jpg",
        "pump-348-gilbarco-circlek-4599-2422l-1899-pump4-ee.jpg",
        "pump-349-gilbarco-circlek-9208-4505l-2044-pump2-ee.jpg",
        "pump-350-gilbarco-circlek-9208-4505l-2044-pump2-second-angle-ee.jpg",
        "pump-351-gilbarco-circlek-4127-2019l-2044-pump1-ee.jpg",
        "pump-352-gilbarco-circlek-4088-2000l-2044-pump3-preset-ee.jpg",
        "pump-353-gilbarco-circlek-7001-3425l-2044-pump5-washed-price-ee.jpg",
        "pump-354-tokheim-olerex-tft-4119-2020l-2039-pump4-ee.jpg",
        "pump-355-tokheim-olerex-peetri-tft-2223-1090l-2039-pump3-pair-ee.jpg",
        "pump-356-tokheim-olerex-peetri-tft-2223-1090l-2039-pump3-pair-second-angle-ee.jpg",
        // 2026-09-28, batch 15 (debug case Q70Z4-SF8JH): Circle K Petrooleumi Gilbarco heads in
        // low sun; pump-359 is the pair of receipt-102.
        "pump-357-gilbarco-circlek-petrooleumi-1954-940l-2079-pump5-ee.jpg",
        "pump-358-gilbarco-circlek-petrooleumi-1196-571l-2094-pump6-ee.jpg",
        "pump-359-gilbarco-circlek-petrooleumi-16548-7198l-2299-pump2-pair-ee.jpg",
        // 2026-09-28, batch 16: Circle K Peterburi - a truck-lane LCD behind reflective glass
        // (two fills, two angles each) and four Gilbarco heads, one of them AdBlue.
        "pump-360-trucklane-lcd-circlek-peterburi-13212-6008l-2199-reflection-ee.jpg",
        "pump-361-trucklane-lcd-circlek-peterburi-13212-6008l-2199-second-angle-ee.jpg",
        "pump-362-trucklane-lcd-circlek-peterburi-44460-20357l-2184-cropped-reflection-ee.jpg",
        "pump-363-trucklane-lcd-circlek-peterburi-44460-20357l-2184-ee.jpg",
        "pump-364-gilbarco-circlek-peterburi-11008-5075l-2169-pump4-ee.jpg",
        "pump-365-gilbarco-circlek-peterburi-2046-937l-price-glare-ee.jpg",
        "pump-366-gilbarco-circlek-peterburi-89954-41000l-2194-pump13-ee.jpg",
        "pump-367-gilbarco-circlek-peterburi-adblue-2977-3104l-ee.jpg",
    ]
}
