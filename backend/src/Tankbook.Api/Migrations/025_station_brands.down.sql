-- Reverses migration 025: drops the station brand vocabulary and its pack state.

DROP TABLE IF EXISTS station_brands;
DROP TABLE IF EXISTS station_brand_pack_state;
