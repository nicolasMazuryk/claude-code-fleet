---
name: binance-subkey-ip-manual
description: Binance sub-account API-key IP restriction cannot be set via master API — manual web-UI only
metadata:
  type: project
---

Setting a Binance **sub-account** API key's IP allow-list via the master API does **not work** for these accounts:
- `POST /sapi/v2/sub-account/subAccountApi/ipRestriction` (status=2, comma list) → `-9000 "Illegel IP address."`
- `POST /sapi/v1/sub-account/subAccountApi/ipRestriction/ipList` (add) → `100001002 "不支持的操作"` (unsupported operation)

`GET /sapi/v1/sub-account/subAccountApi/ipRestriction` and the `DELETE .../ipList` (remove) **do** work.

**How to apply:** Binance sub-key IP changes are manual web-UI (or `binance-cli` if installed on `.61`). The DELETE-remove path works programmatically, but adding a new IP must be done in the UI. When updating the allow-list, add the new IP in the UI *before* removing the old one to avoid a window with only one IP. The other 5 exchanges (gateio/kucoin/okx/bitget/bybit) support programmatic IP update via `normalize-keys` — see [[prov-cli-on-server]].
