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
            // 2026-09-21: four Russian receipts from the same intake.
            "receipt-079-tatneft-transazs-mkad-92-mir-ru.jpg",
            "receipt-080-alfaoil-gazpromneft-33088-92-folded-unrolled-ru.jpg",
            "receipt-081-gazpromneft-alfaoil-33088-92-hand-ru.jpg",
            "receipt-082-lukoil-centrnefteprodukt-kievskoe-ekto95-discount-ru.jpg",
            "receipt-083-circlek-peetri-pump1-d-b0-miles-4325l-2099-ee.jpg",
            "receipt-084-circlek-peetri-pump3-d-b0-miles-2143l-2099-pair-ee.jpg",
            "receipt-085-circlek-peetri-pump5-98miles-1790l-1959-discount-pair-ee.jpg",
            "receipt-086-circlek-peetri-night-pump4-95eo-miles-3497l-1999-pair-ee.jpg",
            "receipt-087-circlek-peetri-night-pump3-98eo-miles-800l-2059-pair-ee.jpg",
            // 2026-09-22 and 2026-09-23 intakes (batches 8-10): Circle K pairs, and
            // Luxembourg/France tickets. Declared, not swept - the A/B arms are frozen.
            "receipt-088-circlek-sikupilli-pump7-d-b0-miles-4089l-2199-pair-ee.jpg",
            "receipt-089-circlek-jarvevana-pump2-95eo-miles-1479l-2024-pair-ee.jpg",
            "receipt-090-total-frisange-excellium98-5124l-1068-lu.jpg",
            "receipt-091-aral-merl-ultimate102-4450l-1264-german-lu.jpg",
            "receipt-092-total-frisange-excellium98-4500l-1134-lu.jpg",
            "receipt-093-totalenergies-stmichel-two-tickets-e85-sp95e10-1851l-1645-fr.jpg",
            "receipt-094-aral-bettembourg-ultimate102-4975l-1582-kopie-lu.jpg",
            "receipt-095-leclerc-chambly-gazole-5210l-1689-pen-marks-fr.jpg",
            "receipt-096-unknown-gazole-3463l-1843-no-total-cropped-fr.jpg",
            "receipt-097-totalenergies-cotesaintandre-dieselexc-3843l-2250-avantage-highlighter-fr.jpg",
            // 2026-09-25: the Capture lab's first run, high1080 preset, the
            // paper half of pump-336, held sideways.
            "receipt-098-circlek-sikupilli-db0-pump8-1400l-2144-extra-soodus-sideways-high1080-pair-ee.jpg",
            // 2026-09-27, batch 14: Circle K Tammisaare and the Olerex Peetri pair (the same
            // paper upright and sideways).
            "receipt-099-circlek-tammisaare-95miles-pump1-4681l-1884-extra-soodus-ee.jpg",
            "receipt-100-olerex-peetri-diesel-1090l-2039-pair-ee.jpg",
            "receipt-101-olerex-peetri-diesel-1090l-2039-pair-sideways-ee.jpg",
            // 2026-09-28, batch 15: the paper half of pump-359, and receipt-099's paper shot
            // again indoors, crumpled, at 1080x1920.
            "receipt-102-circlek-petrooleumi-diesel-7198l-2299-pair-ee.jpg",
            "receipt-103-circlek-tammisaare-95miles-4681l-1884-second-shot-crumpled-ee.jpg",
            // 2026-09-28: the Capture lab's second run (one Circle K Peterburi receipt at the
            // default, zoom2x and high1080 presets), then batch 16's two Circle K Peterburi receipts.
            "receipt-104-circlek-peterburi-diesel-4161l-2184-ee.jpg",
            "receipt-105-circlek-peterburi-diesel-4161l-2184-zoom2x-total-cut-ee.jpg",
            "receipt-106-circlek-peterburi-diesel-4161l-2184-1080p-ee.jpg",
            "receipt-107-circlek-peterburi-diesel-802l-2169-extra-soodus-ee.jpg",
            "receipt-108-circlek-peterburi-diesel-3219l-2184-ee.jpg",
            // 2026-09-30, batch 18: Alexela Sikupilli diesel, Neste Vesse Futura D (the paper of
            // pump-371) and Neste Vesse AdBlue.
            "receipt-109-alexela-sikupilli-diesel-1508l-2059-ee.jpg",
            "receipt-110-neste-vesse-futura-d-1500l-2089-pair-ee.jpg",
            "receipt-111-neste-vesse-adblue-575l-0899-ee.jpg",
            // Case 3GQZB-BC5VF (2026-09-30): in-app second shots of the batch 18 papers.
            "receipt-112-alexela-sikupilli-diesel-1508l-2059-second-shot-ee.jpg",
            "receipt-113-neste-vesse-futura-d-1500l-2089-second-shot-pair-ee.jpg",
            "receipt-114-neste-vesse-adblue-575l-0899-second-shot-ee.jpg"
        ],
        "pump": pump,
        "screenshots": [
            // 2026-09-14: an OFD-rendered Lukoil AI-100 e-receipt. Declared,
            // not swept - the A/B arms remain frozen.
            "screenshot-009-lukoil-ekaterinburg-ai100-ru.png",
        ],
    ]

    static func forClass(_ name: String) -> Set<String> { byClass[name] ?? [] }
}
