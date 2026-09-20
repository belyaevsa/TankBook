import Foundation

/// Images added to the corpus **after** the 2026-08-26 A/B sweep, per class.
/// Adding a fixture means adding it here, which is the deliberate act that keeps
/// corpus growth from silently shrinking the A/B's coverage.
enum PostSweepCorpusAdditions {
    /// 2026-08-27, the Татнефть АЗС-172 triplet (one 25 L / 99.99 RUB fill shot
    /// three ways) and the Circle K Sikupilli set (a matched receipt/pump pair,
    /// a zero-volume receipt, and three sun-glared Wayne displays). See
    /// `Spike/ReceiptSpike/fixtures/receipts/README.md` and `pump/README.md`.
    static let byClass: [String: Set<String>] = [
        "receipts": [
            // 2026-09-09: the owner's own fills. receipt-053/pump-074,
            // receipt-054/pump-075 and receipt-055/pump-076 are three matched
            // receipt/pump pairs of the SAME fill; 056 is a zero receipt and
            // 057 has its unit price under a thumb. Declared, not swept - the
            // A/B arms are frozen.
            "receipt-053-gpn-tver-95-ru.jpg",
            "receipt-054-circlek-tallinn-95-et.jpg",
            "receipt-055-circlek-tallinn-98-discount-et.jpg",
            "receipt-056-circlek-tallinn-zero-et.jpg",
            "receipt-057-gpn-valday-95-occluded-ru.jpg",
            "receipt-036-tatneft-azs172-98-terminal-slip-ru.jpeg",
            "receipt-037-tatneft-azs172-98-vat22-qr-ru.jpeg",
            "receipt-038-circlek-sikupilli-95e0-pump8-ee.jpg",
            "receipt-039-circlek-sikupilli-zero-volume-pump7-ee.jpg",
            // The matched half of pump-029: same fill, same forecourt, same
            // minute. Declared, not swept - the A/B arms are frozen.
            "receipt-040-gpn-okulovka-gdrive95-fuelcard-ru.jpg",
            // 2026-08-30: the matched half of pump-030 - same fill, same
            // minute, a Tver fuel card. Declared, not swept.
            "receipt-041-zolotaya-seredina-tver-95-fuelcard-ru.jpg",
            // 2026-08-31: the matched half of pump-034 - Circle K Jarvevana,
            // Tallinn, 87.29 L of D B0 at 1.839. Declared, not swept.
            "receipt-042-circlek-jarvevana-tallinn-db0-pump7-ee.jpg",
            // 2026-09-01: a Sverdlovsk AI-95 receipt reposted through a news
            // channel, so a watermark is composited OVER the product line.
            // Declared, not swept.
            "receipt-043-artemovsk-gazservis-95-vat22-watermark-ru.jpg",
            // 2026-09-03: a Russian NON-FISCAL terminal slip (the matched half
            // of pump-044, and the corpus's first of that class - no fiscal QR
            // exists on one), and the paper half of pump-054, whose printed
            // total is a cent above litres x price. Declared, not swept.
            "receipt-044-rn-tver-chkalovskaya-95-nonfiscal-terminal-slip-ru.jpeg",
            "receipt-045-circlek-jarvevana-pump7-db0-2694l-ee.jpg",
            // 2026-09-04: the matched half of pump-057 - Circle K Sikupilli,
            // pump 5, 55.80 L of D B0 miles at 1.799 = 100.38, VAT 24%.
            // Declared, not swept.
            "receipt-046-circlek-sikupilli-pump5-db0-5580l-ee.jpg",
            // 2026-09-04: the matched halves of pump-065 and pump-066 - two RU
            // fills shot the same day, each photographed at the pump and on
            // paper. They bracket the RUB price band: 048's 15 L falls below
            // the 40 floor and sweeps 5/5, 047's 53 L sits inside it and
            // abstains on both operands. Declared, not swept - the arms are
            // frozen, and these arrived at 1280 px through Telegram.
            "receipt-047-gazpromneft-edrovo-gdrive95-fuelcard-pair-ru.jpeg",
            "receipt-048-rn-tver-budovo-95-nonfiscal-terminal-slip-pair-ru.jpeg",
            // 2026-09-07 (RV.114): the paper halves of pump-067 and pump-068
            // - one Circle K Jarvevana session, Pump 4 and Pump 7 - plus a
            // Gazpromneft G-Drive 95 fuel-card slip shot UPSIDE DOWN, the
            // corpus's first 180-degree rotation. Declared, not swept: the
            // A/B arms stay frozen at their pinned numbers, and RV.114 owns
            // scoring these against the harness.
            "receipt-049-circlek-jarvevana-pump4-95miles-4837l-pair-ee.jpg",
            "receipt-050-circlek-jarvevana-pump7-db0-7070l-rotated90-pair-ee.jpg",
            "receipt-051-gazpromneft-tver-gdrive95-fuelcard-rotated180-ru.jpg",
            // 2026-09-07: the paper half of pump-073 - one Gazpromneft Tver
            // G-Drive 95 fuel-card fill, 32.000 L at 70.31 for 2249.92 RUB,
            // whose pump prints the total one digit short. Declared, not swept.
            "receipt-052-gazpromneft-tver-gdrive95-fuelcard-pair-ru.jpeg",
            // 2026-09-10: two Circle K Peetri slips printed one minute apart on
            // two tills (058 is 98E0, 059 is the corpus's smallest non-zero
            // fill at 7.68 L, shot at night with a shadow across it), and the
            // paper half of pump-083 - a Gazpromneft AZS 12089 fuel-card fill
            // whose pump truncates the total to 0.1 RUB. Declared, not swept.
            "receipt-058-circlek-peetri-98e0-pump7-4353l-ee.jpg",
            "receipt-059-circlek-peetri-db0-pump5-768l-night-wet-ee.jpg",
            "receipt-060-gazpromneft-azs12089-95-fuelcard-pair-ru.jpeg",
            // 2026-09-10: the paper half of pump-084 - a Gazpromneft Okulovka
            // AZS 1010 fuel-card fill whose money line `71.18 x 42.000` is
            // unmarked and whose operands both sit inside the RUB price band,
            // so the parser abstains on volume and price. Declared, not swept.
            "receipt-061-gazpromneft-okulovka-azs1010-gdrive95-fuelcard-pair-ru.jpeg",
            // 2026-09-11: two RN-Tver Chkalovskaya non-fiscal fuel-card slips
            // (the paper halves of pump-085/086, one till, two minutes apart)
            // and the Circle K Peetri slip that pairs with pump-095. Declared,
            // not swept.
            "receipt-062-rn-tver-chkalovskaya-95firm-3000l-nonfiscal-terminal-slip-pair-ru.jpeg",
            "receipt-063-rn-tver-chkalovskaya-95firm-1000l-nonfiscal-terminal-slip-pair-ru.jpeg",
            "receipt-064-circlek-peetri-db0-pump5-2307l-pair-ee.jpg",
            // 2026-09-13: the paper half of pump-096 - a non-fiscal PetrolPlus
            // slip from the same till family and legend as 062/063, one RN-Tver
            // station over. Declared, not swept.
            "receipt-065-rn-tver-tc252-95firm-2000l-nonfiscal-terminal-slip-pair-ru.jpeg",
            // 2026-09-13: the paper half of pump-100 - a Circle K Jarvevana
            // slip whose printed per-litre price already carries the discount,
            // so 64.04 x 2.024 = 129.62 closes exactly. Declared, not swept.
            "receipt-066-circlek-jarvevana-db0-pump4-6404l-pair-ee.jpg",
            // 2026-09-14: the paper half of pump-104 - Circle K Sikupilli,
            // pump 1, 26.50 L of 95E0 at 1.949 = 51.65. Declared, not swept.
            "receipt-067-circlek-sikupilli-95e0-pump1-2650l-pair-ee.jpg",
            // 2026-09-18: six Telegram-routed Russian fuel-card slips. 068/069
            // are the terminal slip and the order slip of ONE RN-Tver AZK 15
            // fill (30.00 L at 68.30 = 2049.00), both photographed sideways;
            // 072/073 are the same two-slip shape at Chkalovskaya (15.00 L at
            // 71.30 = 1069.50, the order slip prints `1 069.50` with a
            // thousands space); 070 is the paper half of pump-109 (Edrovo,
            // 48.000 x 71.05) and 071 the paper half of pump-110 (42.000 x
            // 70.31), its station header cut off. Declared, not swept.
            "receipt-068-rn-tver-azk15-95-3000l-nonfiscal-terminal-slip-sideways-pair-ru.jpeg",
            "receipt-069-rn-tver-azk15-95k5-3000l-nonfiscal-order-slip-sideways-pair-ru.jpeg",
            "receipt-070-gazpromneft-edrovo-azs10031-gdrive95-fuelcard-pair-ru.jpeg",
            "receipt-071-gazpromneft-gdrive95-fuelcard-header-cut-pair-ru.jpeg",
            "receipt-072-rn-tver-chkalovskaya-95firm-1500l-nonfiscal-terminal-slip-pair-ru.jpeg",
            "receipt-073-rn-tver-chkalovskaya-pulsar95-1500l-nonfiscal-order-slip-pair-ru.jpeg",
            // 2026-09-19/20: the two Sikupilli pair receipts, then the first
            // third-party receipts (Rosneft 2013, TotalEnergies BE, an
            // independent RU station). Declared, not swept.
            "receipt-074-circlek-sikupilli-98miles-pump7-1517l-pair-ee.jpg",
            "receipt-075-circlek-sikupilli-98miles-pump8-2786l-pair-ee.jpg",
            "receipt-076-rosneft-vostoknefteprodukt-92-cash-third-party-ru.jpg",
            "receipt-077-totalenergies-kalken-excel-diesel-card-third-party-be.jpg",
            "receipt-078-kiselev-independent-92-ten-litres-two-receipts-third-party-ru.jpg",
        ],
        "pump": [
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
        ],
        "screenshots": [
            // 2026-09-14: an OFD-rendered Lukoil AI-100 e-receipt. Declared,
            // not swept - the A/B arms remain frozen.
            "screenshot-009-lukoil-ekaterinburg-ai100-ru.png",
        ],
    ]

    static func forClass(_ name: String) -> Set<String> { byClass[name] ?? [] }
}
