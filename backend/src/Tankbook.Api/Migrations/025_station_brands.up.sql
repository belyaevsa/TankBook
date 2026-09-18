-- Tankbook backend, migration 025 (station brand vocabulary, RV.115).
--
-- docs/API.md "GET /reference/station-brands", docs/SYNC.md "Reference data".
-- A curated list of fuel and charging BRANDS with their alias spellings, so
-- four spellings of one chain (Газпром / Газпромнефть / Gazpromneft / G-Drive)
-- group as one brand on the device. Brands, never individual forecourts: a
-- station stays a per-account Station entity; only its `brand` is set from this
-- list, by the DEVICE's matcher, at the moment the station is created.
--
-- Same shape as vehicle_catalog + catalog_pack_state (migrations 001/011): one
-- row per brand keyed by a stable id, pack_version per row for the delta, and a
-- singleton state row that IS the current pack version. A later correction
-- upserts the id in place and bumps its pack_version; the GET serves the delta
-- above a client's held version or the full pack.
--
-- Three things this data is NOT (CLAUDE.md hard rules 9 and 13):
--   * a matched brand is a DEFAULT the device offers when a station is created.
--     A brand the user set or cleared is theirs; republishing this pack changes
--     what the NEXT station matches and never rewrites a saved one.
--   * the server curates; it does not interpret. Nothing here is read by an
--     endpoint - the match runs on the device.
--   * a name matching nothing is a first-class state (a station with no brand),
--     not an error the list exists to prevent.
--
-- `country` is the brand's home market (ISO 3166-1 alpha-2), for the device's
-- relevance ordering (docs/API.md). Aliases are matched as whole tokens, case-
-- and script-insensitively, by the device (`StationBrandMatcher`).
-- ON CONFLICT keeps the migration re-runnable against a table that already
-- carries these rows.

CREATE TABLE station_brands (
    id           text PRIMARY KEY,
    name         text NOT NULL,
    country      char(2) NOT NULL,
    aliases      text[] NOT NULL DEFAULT ARRAY[]::text[],
    pack_version int NOT NULL
);

CREATE INDEX idx_station_brands_pack_version ON station_brands (pack_version);

CREATE TABLE station_brand_pack_state (
    singleton    int PRIMARY KEY CHECK (singleton = 1),
    pack_version int NOT NULL
);

INSERT INTO station_brand_pack_state (singleton, pack_version) VALUES (1, 1);

INSERT INTO station_brands (id, name, country, aliases, pack_version)
SELECT id, name, country, aliases, 1 FROM (VALUES
    ('gazpromneft', 'Gazpromneft', 'RU', ARRAY['Газпромнефть','Газпром нефть','Газпром','Gazprom','G-Drive','ГПН','Газпромнефть-Центр','Газпромнефть-Урал','Газпромнефть-Северо-Запад']::text[]),
    ('lukoil', 'Lukoil', 'RU', ARRAY['Лукойл','ЛУКОЙЛ','Лукойл-Центрнефтепродукт','Лукойл-Югнефтепродукт','Лукойл-Уралнефтепродукт','Ликард']::text[]),
    ('rosneft', 'Rosneft', 'RU', ARRAY['Роснефть','РН-Карт','Rosneft-Card']::text[]),
    ('tatneft', 'Tatneft', 'RU', ARRAY['Татнефть','Татнефть-АЗС Центр','Татнефть-АЗС-Запад']::text[]),
    ('bashneft', 'Bashneft', 'RU', ARRAY['Башнефть','Башнефть-Розница']::text[]),
    ('teboil', 'Teboil', 'RU', ARRAY['Тебойл','Teboil Rus']::text[]),
    ('neftmagistral', 'Neftmagistral', 'RU', ARRAY['Нефтьмагистраль','Нефть магистраль']::text[]),
    ('surgutneftegas', 'Surgutneftegas', 'RU', ARRAY['Сургутнефтегаз','СНГ']::text[]),
    ('eka', 'EKA', 'RU', ARRAY['ЕКА','ЕКА-АЗС']::text[]),
    ('trassa', 'Trassa', 'RU', ARRAY['Трасса','Трасса-АЗС']::text[]),
    ('opti', 'OPTI', 'RU', ARRAY['ОПТИ','Опти']::text[]),
    ('tnk', 'TNK', 'RU', ARRAY['ТНК','ТНК-BP']::text[]),
    ('irkutskoil', 'Irkutsk Oil', 'RU', ARRAY['Иркутская нефтяная компания','ИНК','Крайснефть']::text[]),
    ('nnk', 'NNK', 'RU', ARRAY['ННК','Альянс','Альянс-Нефтепродукт']::text[]),
    ('magistral', 'Magistral', 'RU', ARRAY['Магистраль']::text[]),
    ('kalina-oil', 'Kalina Oil', 'RU', ARRAY['Калина Ойл','Калина-Ойл']::text[]),
    ('fuel-star', 'Petrol Star', 'RU', ARRAY['Петрол Стар']::text[]),
    ('qazaqoil', 'Qazaq Oil', 'KZ', ARRAY['QazaqOil','Казак Ойл','Қазақ Ойл','Qazaq Oil KZ']::text[]),
    ('kazmunaygas', 'KazMunayGas', 'KZ', ARRAY['КазМунайГаз','ҚазМұнайГаз','KMG','КМГ','ҚМГ','КазМунайГаз Аймак']::text[]),
    ('helios', 'Helios', 'KZ', ARRAY['Гелиос','Helios KZ','Гелиос АЗС']::text[]),
    ('sinooil', 'Sinooil', 'KZ', ARRAY['Синойл','Sino Oil','СИНООЙЛ']::text[]),
    ('royal-petrol', 'Royal Petrol', 'KZ', ARRAY['Роял Петрол','RoyalPetrol']::text[]),
    ('petro-retail', 'PetroRetail', 'KZ', ARRAY['ПетроРитейл','Petro Retail','Petroretail']::text[]),
    ('compass-kz', 'Compass', 'KZ', ARRAY['Компас','Compass KZ']::text[]),
    ('green-kz', 'Green', 'KZ', ARRAY['Грин','Green АЗС']::text[]),
    ('petrol-asia', 'Petrol Asia', 'KZ', ARRAY['Петрол Азия','PetrolAsia']::text[]),
    ('aidyn', 'Aidyn', 'KZ', ARRAY['Айдын','Айдын Мунай']::text[]),
    ('dostyk', 'Dostyk', 'KZ', ARRAY['Достык','Достық']::text[]),
    ('circle-k', 'Circle K', 'EE', ARRAY['CircleK','Circle-K','Statoil','Сёркл Кей','Circle K Sikupilli','Circle K Eesti','Circle K Latvia','Circle K Lietuva']::text[]),
    ('neste', 'Neste', 'FI', ARRAY['Neste Oil','Neste Eesti','Neste Latvija','Neste Lietuva','Neste Express','Несте']::text[]),
    ('olerex', 'Olerex', 'EE', ARRAY['Olerex AS','Олерекс']::text[]),
    ('alexela', 'Alexela', 'EE', ARRAY['Alexela Energia','Алексела']::text[]),
    ('terminal-oil', 'Terminal', 'EE', ARRAY['Terminal Oil','Terminal Tanklad']::text[]),
    ('viada', 'Viada', 'LT', ARRAY['Viada Baltija','Viada LT','Виада']::text[]),
    ('virsi', 'Virši', 'LV', ARRAY['Virsi','Viršī','Virši-A']::text[]),
    ('orlen', 'Orlen', 'PL', ARRAY['PKN Orlen','Orlen Lietuva','Orlen Deutschland','Орлен']::text[]),
    ('abc-fi', 'ABC', 'FI', ARRAY['ABC-asema','ABC Prisma','S-market ABC']::text[]),
    ('st1', 'St1', 'FI', ARRAY['St1 Oy','St1 Way','Shell St1']::text[]),
    ('omv', 'OMV', 'AT', ARRAY['О-Эм-Ви','OMV Slovensko','OMV Česko']::text[]),
    ('mol', 'MOL', 'HU', ARRAY['MOL Group','INA','МОЛ']::text[]),
    ('petrom', 'Petrom', 'RO', ARRAY['OMV Petrom','Petrom SA']::text[]),
    ('rompetrol', 'Rompetrol', 'RO', ARRAY['Rompetrol Downstream','KMG Rompetrol']::text[]),
    ('lotos', 'Lotos', 'PL', ARRAY['Grupa Lotos','Lotos Paliwa']::text[]),
    ('moya', 'Moya', 'PL', ARRAY['Moya Stacja']::text[]),
    ('benzina', 'Benzina', 'CZ', ARRAY['Benzina Orlen','Benzina a.s.']::text[]),
    ('eurooil', 'EuroOil', 'CZ', ARRAY['Euro Oil','Čepro EuroOil']::text[]),
    ('slovnaft', 'Slovnaft', 'SK', ARRAY['Slovnaft a.s.']::text[]),
    ('petrol-si', 'Petrol', 'SI', ARRAY['Petrol d.d.','Petrol Slovenija']::text[]),
    ('wog', 'WOG', 'UA', ARRAY['ВОГ','WOG Retail']::text[]),
    ('okko', 'OKKO', 'UA', ARRAY['ОККО','Okko Group']::text[]),
    ('socar', 'SOCAR', 'AZ', ARRAY['Сокар','SOCAR Energy','SOCAR Georgia','SOCAR Ukraine']::text[]),
    ('belorusneft', 'Belorusneft', 'BY', ARRAY['Белоруснефть','Беларуснафта']::text[]),
    ('shell', 'Shell', 'NL', ARRAY['Royal Dutch Shell','Shell V-Power','Shell Express','Шелл','Shell Deutschland','Shell UK']::text[]),
    ('bp', 'BP', 'GB', ARRAY['British Petroleum','BP Ultimate','БП','Aral BP']::text[]),
    ('aral', 'Aral', 'DE', ARRAY['Aral AG','Арал']::text[]),
    ('esso', 'Esso', 'GB', ARRAY['Esso Express','Esso Deutschland','Эссо']::text[]),
    ('totalenergies', 'TotalEnergies', 'FR', ARRAY['Total','Total Energies','TotalEnergies Access','Total Access','Тоталь']::text[]),
    ('eni', 'Eni', 'IT', ARRAY['Agip','Eni Station','Agip Eni','Эни']::text[]),
    ('q8', 'Q8', 'KW', ARRAY['Kuwait Petroleum','Q8 Easy','Q8 Tankstation']::text[]),
    ('jet', 'JET', 'DE', ARRAY['Jet Tankstelle','JET UK','Conoco JET']::text[]),
    ('avia', 'AVIA', 'CH', ARRAY['Avia International','AVIA Tankstelle']::text[]),
    ('star-orlen', 'star', 'DE', ARRAY['star Tankstelle','star Orlen']::text[]),
    ('hem', 'HEM', 'DE', ARRAY['HEM Tankstelle','Deutsche Tamoil HEM']::text[]),
    ('tamoil', 'Tamoil', 'NL', ARRAY['Tamoil Nederland','Tamoil Italia']::text[]),
    ('westfalen', 'Westfalen', 'DE', ARRAY['Westfalen AG','Westfalen Tankstelle']::text[]),
    ('repsol', 'Repsol', 'ES', ARRAY['Repsol Campsa','Репсол']::text[]),
    ('cepsa', 'Cepsa', 'ES', ARRAY['Moeve','Cepsa Estación']::text[]),
    ('galp', 'Galp', 'PT', ARRAY['Galp Energia']::text[]),
    ('bft', 'bft', 'DE', ARRAY['bft Tankstelle','Bundesverband freier Tankstellen']::text[]),
    ('tinq', 'Tinq', 'NL', ARRAY['TinQ','TinQ Tankstation']::text[]),
    ('texaco', 'Texaco', 'GB', ARRAY['Texaco UK','Тексако']::text[]),
    ('gulf', 'Gulf', 'GB', ARRAY['Gulf Oil','Gulf UK']::text[]),
    ('tesco-fuel', 'Tesco', 'GB', ARRAY['Tesco Petrol','Tesco Extra Petrol','Tesco Fuel']::text[]),
    ('sainsburys-fuel', 'Sainsbury''s', 'GB', ARRAY['Sainsburys','Sainsbury''s Petrol']::text[]),
    ('asda-fuel', 'Asda', 'GB', ARRAY['Asda Petrol','Asda Express']::text[]),
    ('morrisons-fuel', 'Morrisons', 'GB', ARRAY['Morrisons Petrol','Morrisons Daily']::text[]),
    ('applegreen', 'Applegreen', 'IE', ARRAY['Apple Green']::text[]),
    ('maxol', 'Maxol', 'IE', ARRAY['Maxol Group']::text[]),
    ('ingo', 'Ingo', 'SE', ARRAY['INGO Sverige','INGO Danmark']::text[]),
    ('okq8', 'OKQ8', 'SE', ARRAY['OK Q8','OKQ8 Sverige']::text[]),
    ('preem', 'Preem', 'SE', ARRAY['Preem AB']::text[]),
    ('uno-x', 'Uno-X', 'NO', ARRAY['UnoX','Uno X']::text[]),
    ('yx', 'YX', 'NO', ARRAY['YX Norge','YX 7-Eleven']::text[]),
    ('migrol', 'Migrol', 'CH', ARRAY['Migrol AG','Migrolino']::text[]),
    ('coop-pronto', 'Coop Pronto', 'CH', ARRAY['Coop Tankstelle']::text[]),
    ('turmoel', 'Turmöl', 'AT', ARRAY['Turmoel','Turmöl Tankstelle']::text[]),
    ('avanti', 'Avanti', 'AT', ARRAY['Avanti Tankstelle']::text[]),
    ('intermarche-fuel', 'Intermarché', 'FR', ARRAY['Intermarche','Intermarché Station']::text[]),
    ('leclerc-fuel', 'E.Leclerc', 'FR', ARRAY['Leclerc','Leclerc Station','E Leclerc']::text[]),
    ('carrefour-fuel', 'Carrefour', 'FR', ARRAY['Carrefour Station','Carrefour Market Station']::text[]),
    ('auchan-fuel', 'Auchan', 'FR', ARRAY['Auchan Station']::text[]),
    ('chevron', 'Chevron', 'US', ARRAY['Chevron Texaco','Chevron with Techron']::text[]),
    ('exxonmobil', 'ExxonMobil', 'US', ARRAY['Exxon','Mobil','Exxon Mobil','Mobil 1']::text[]),
    ('sunoco', 'Sunoco', 'US', ARRAY['Sunoco APlus']::text[]),
    ('marathon', 'Marathon', 'US', ARRAY['Marathon Petroleum','Marathon Gas']::text[]),
    ('speedway', 'Speedway', 'US', ARRAY['Speedway Gas']::text[]),
    ('valero', 'Valero', 'US', ARRAY['Valero Energy']::text[]),
    ('phillips-66', 'Phillips 66', 'US', ARRAY['Phillips66','Conoco','Union 76']::text[]),
    ('citgo', 'Citgo', 'US', ARRAY['CITGO Petroleum']::text[]),
    ('costco-fuel', 'Costco', 'US', ARRAY['Costco Gas','Costco Gasoline']::text[]),
    ('sams-club-fuel', 'Sam''s Club', 'US', ARRAY['Sams Club','Sam''s Club Fuel']::text[]),
    ('wawa', 'Wawa', 'US', ARRAY['Wawa Fuel']::text[]),
    ('sheetz', 'Sheetz', 'US', ARRAY[]::text[]),
    ('7-eleven-fuel', '7-Eleven', 'US', ARRAY['7 Eleven','Seven Eleven','7-11']::text[]),
    ('caseys', 'Casey''s', 'US', ARRAY['Caseys','Casey''s General Store']::text[]),
    ('kwik-trip', 'Kwik Trip', 'US', ARRAY['KwikTrip','Kwik Star']::text[]),
    ('quiktrip', 'QuikTrip', 'US', ARRAY['Quik Trip','QT']::text[]),
    ('racetrac', 'RaceTrac', 'US', ARRAY['Race Trac','RaceWay']::text[]),
    ('buc-ees', 'Buc-ee''s', 'US', ARRAY['Bucees','Buc-ees']::text[]),
    ('pilot-flying-j', 'Pilot Flying J', 'US', ARRAY['Pilot','Flying J','Pilot Travel Center']::text[]),
    ('loves', 'Love''s', 'US', ARRAY['Loves','Love''s Travel Stop']::text[]),
    ('arco', 'ARCO', 'US', ARRAY['Arco ampm','ampm']::text[]),
    ('petro-canada', 'Petro-Canada', 'CA', ARRAY['Petro Canada','PetroCanada']::text[]),
    ('husky', 'Husky', 'CA', ARRAY['Husky Energy']::text[]),
    ('pemex', 'Pemex', 'MX', ARRAY['Petróleos Mexicanos']::text[]),
    ('tesla-supercharger', 'Tesla Supercharger', 'US', ARRAY['Tesla','Supercharger','Tesla Charging']::text[]),
    ('ionity', 'Ionity', 'DE', ARRAY['IONITY']::text[]),
    ('enbw', 'EnBW', 'DE', ARRAY['EnBW mobility+','EnBW HyperNetz']::text[]),
    ('fastned', 'Fastned', 'NL', ARRAY[]::text[]),
    ('electra', 'Electra', 'FR', ARRAY[]::text[]),
    ('chargepoint', 'ChargePoint', 'US', ARRAY['Charge Point']::text[]),
    ('electrify-america', 'Electrify America', 'US', ARRAY[]::text[]),
    ('evgo', 'EVgo', 'US', ARRAY['EV go']::text[]),
    ('gridserve', 'Gridserve', 'GB', ARRAY['Gridserve Electric Highway']::text[]),
    ('eleport', 'Eleport', 'EE', ARRAY[]::text[]),
    ('enefit-volt', 'Enefit Volt', 'EE', ARRAY['Enefit','Eesti Energia']::text[])
) AS seed (id, name, country, aliases)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    country = EXCLUDED.country,
    aliases = EXCLUDED.aliases,
    pack_version = EXCLUDED.pack_version;
