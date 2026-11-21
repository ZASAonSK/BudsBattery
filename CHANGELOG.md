# Changelog

## 1.0.0 — first release

- Battery of the left earbud, right earbud and charging case, with a live / last-seen status.
- Guided setup: open the case near the phone and pick your earbuds from the list.
- Two data sources: the Bluetooth broadcast (foreground) and the GATT Battery Service while the earbuds are connected (preferred).
- Trend (rising / falling), rough remaining-time estimate and a battery history chart.
- Liquid Glass design on iOS 26+, material fallback on iOS 16 to 25.
- 11 languages that follow the phone's language (English by default).

The broadcast layout was inferred from captured Galaxy Buds3 Pro advertisements and is not a published protocol. ANC control, in-ear detection and charging state need the RFCOMM link that iOS does not open to third-party apps and are therefore not available.
