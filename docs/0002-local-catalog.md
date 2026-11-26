# ADR 0002: on-device national catalog

Status: accepted. Supersedes the "live Overpass only" part of [ADR 0001](0001-search-and-privacy.md).

## Context

Both public Overpass endpoints failed in a real smoke test, and every live query shares an approximate location
with a third party. The web app already publishes a validated national extract every week.

## Decision

- **Bundle** the same `finland-pharmacies.json` (Geofabrik Finland extract, filtered to `amenity=pharmacy`,
  ODbL 1.0) as a resource of `PharmacyCore`, loaded through `Bundle.module`.
- **Search it on the device.** The snapshot is decoded once per launch; every result within 30 km is ranked by
  distance. Because the snapshot contains every mapped pharmacy, a result in range is proven nearest.
- **Refresh without location.** When the snapshot in use is more than seven days old, the app downloads
  `https://pharmanear-web.vercel.app/data/current-finland-pharmacies.json` (4 s limit, ephemeral session, no
  cookies or cache). A newer valid snapshot replaces the bundled one in memory for the rest of the launch. After
  a failed attempt the app waits an hour before trying again, so an offline phone is not slowed down on every
  search.
- **Expire.** A snapshot older than 30 days is never used.
- **Fall back** to live Overpass (ADR 0001) only when no usable snapshot exists or it has nothing within 30 km.

## Consequences

- Searches work offline and send no location while a snapshot is fresh.
- The app depends on the web deployment for freshness; without it, a build older than 30 days falls back to
  live search. Releases should bundle the current file from the web repository.
- The refreshed snapshot is not written to disk. Persisting it would remove one download per launch after the
  first week; it was left out until there is evidence it matters.
