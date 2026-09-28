# Tracker hosts

The hosts `privacy-auditor` names as **trackers**. A request to one of these,
or to any subdomain of one, is a tracker. Other third parties are listed in
the evidence but do not fail a case on their own. Extend the list per project
with `privacy.trackers` in `tests/framework.json`, and exempt a host with
`privacy.allow_hosts`.

**Analytics and tag managers**

- google-analytics.com
- googletagmanager.com
- analytics.google.com
- stats.g.doubleclick.net
- segment.com, segment.io, cdn.segment.com
- mixpanel.com
- amplitude.com
- heap.io, heapanalytics.com
- plausible.io
- matomo.cloud
- clarity.ms
- hotjar.com, hotjar.io
- fullstory.com
- mouseflow.com
- logrocket.com, lr-ingest.io
- smartlook.com
- posthog.com

**Advertising and social pixels**

- doubleclick.net
- googlesyndication.com
- googleadservices.com
- adservice.google.com
- facebook.net, connect.facebook.net
- facebook.com/tr
- ads-twitter.com
- analytics.twitter.com
- static.ads-twitter.com
- snap.licdn.com
- px.ads.linkedin.com
- bat.bing.com
- tiktok.com/i18n/pixel
- analytics.tiktok.com
- pinimg.com/ct
- ct.pinterest.com
- sc-static.net
- tr.snapchat.com
- criteo.com, criteo.net
- taboola.com
- outbrain.com
- adroll.com
- quantserve.com
- scorecardresearch.com

**Marketing and chat, when they set identifiers before consent**

- hubspot.com, hs-analytics.net, hs-scripts.com
- marketo.net, mktoresp.com
- intercom.io, intercomcdn.com
- drift.com
- crisp.chat
- zdassets.com

A path is a tracker on any host when it looks like one:

- `/collect`
- `/g/collect`
- `/pixel`
- `/tr?` or `/tr/`
- `/track`
- `/beacon`
- `/analytics`
- `/gtag/js`
- `/fbevents.js`
