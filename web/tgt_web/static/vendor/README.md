# Vendored third-party assets

These files ship inside the `tgt-web` wheel so the UI works on
offline / air-gapped pentest boxes. Update procedure for any
dependency below:

```bash
curl -fsSL -o web/tgt_web/static/vendor/<name>-<version>.min.js \
  "https://unpkg.com/<package>@<version>/<dist-path>"
sha256sum web/tgt_web/static/vendor/<name>-<version>.min.js
# update the entry below, commit the diff
```

Bumping a version = a deliberate PR with the file diff visible.
Don't replace the file in-place under the same name.

## Dependencies

### Alpine.js

- **File:** `alpine-3.14.1.min.js`
- **Source:** https://unpkg.com/alpinejs@3.14.1/dist/cdn.min.js
- **Version:** 3.14.1
- **License:** MIT — https://github.com/alpinejs/alpine/blob/main/LICENSE.md
- **SHA-256:** `358d9afbb1ab5befa2f48061a30776e5bcd7707f410a606ba985f98bc3b1c034`
- **Used for:** declarative client state (`x-data`, `x-model`, `x-show`)
  in forms and stateful inline widgets. See `web/ARCHITECTURE.md`
  for when Alpine is and isn't the right tool.
