#!/usr/bin/env bash
# Deploy a static site to S3 with correct content types & cache headers.
# Usage:
#   ./deploy-static.sh s3-bucket-name [cloudfront-distribution-id]
#
# Example:
#   ./deploy-static.sh www.timeandnotes.com E123ABC456DEF
#
# Notes:
# - Uploads from the *current directory* to the bucket root.
# - Sets long-term caching for immutable assets; HTML is no-cache.
# - Special fixed-URL files (robots.txt, favicon.ico, etc.) are re-uploaded LAST with overrides.
# - If a CloudFront Distribution ID is provided, creates an invalidation.

set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found. Install AWS CLI v2 and configure credentials." >&2
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <s3-bucket-name> [cloudfront-distribution-id]" >&2
  exit 1
fi

BUCKET="$1"
CF_DIST_ID="${2-}"   # optional

# Common excludes you probably don’t want to upload
EXCLUDES=(
  "--exclude" ".git/*"
  "--exclude" ".gitignore"
  "--exclude" ".DS_Store"
  "--exclude" "node_modules/*"
)

# Cache controls
CACHE_IMMUTABLE="public,max-age=31536000,immutable"
CACHE_HTML="no-cache, must-revalidate"

# Special-file cache policies (tweak to taste)
CACHE_ROBOTS="public,max-age=3600"           # 1h: crawlers should see updates relatively quickly
CACHE_FAVICON="$CACHE_IMMUTABLE"             # 1y immutable: favicons rarely change
CACHE_SITEMAP="public,max-age=86400"         # 1d: reasonable for search engines
CACHE_SW="no-cache, must-revalidate"         # service workers must update promptly
CACHE_MANIFEST="public,max-age=3600"         # manifests can change without renaming
CACHE_AASA="public,max-age=86400"            # apple-app-site-association / assetlinks.json
CACHE_SECURITY="public,max-age=86400"        # security.txt (well-known)

# Helper to upload a set of extensions with a single metadata rule
#   upload_set "text/css" "$CACHE_IMMUTABLE" css
upload_set() {
  local content_type="$1"; shift
  local cache_control="$1"; shift
  local exts=( "$@" )

  local args=( aws s3 cp . "s3://$BUCKET/" --recursive --only-show-errors \
               --exclude "*" \
               --cache-control "$cache_control" \
               --content-type "$content_type" )

  local had_include=false
  for ext in "${exts[@]}"; do
    args+=( --include "*.${ext}" )
    had_include=true
  done

  args+=( "${EXCLUDES[@]}" )

  if [[ "$had_include" = true ]]; then
    echo "→ Uploading: ${exts[*]} as ${content_type} (cache: $cache_control)"
    "${args[@]}"
  fi
}

# Helper to upload a single, exact path with given metadata if it exists
#   upload_exact "robots.txt" "text/plain; charset=utf-8" "$CACHE_ROBOTS"
upload_exact() {
  local rel_path="$1"
  local content_type="$2"
  local cache_control="$3"

  if [[ -f "$rel_path" ]]; then
    echo "→ Overriding: $rel_path  (type: $content_type; cache: $cache_control)"
    aws s3 cp "$rel_path" "s3://$BUCKET/$rel_path" \
      --only-show-errors \
      --cache-control "$cache_control" \
      --content-type "$content_type"
  fi
}

echo "Deploying current directory to s3://$BUCKET ..."

# 1) Upload immutable/static assets first (long cache)
upload_set "text/css"              "$CACHE_IMMUTABLE" css
upload_set "text/javascript"       "$CACHE_IMMUTABLE" js mjs cjs
upload_set "application/json"      "$CACHE_IMMUTABLE" json map
upload_set "application/manifest+json" "$CACHE_IMMUTABLE" webmanifest
upload_set "image/svg+xml"         "$CACHE_IMMUTABLE" svg
upload_set "image/png"             "$CACHE_IMMUTABLE" png
upload_set "image/jpeg"            "$CACHE_IMMUTABLE" jpg jpeg
upload_set "image/gif"             "$CACHE_IMMUTABLE" gif
upload_set "image/webp"            "$CACHE_IMMUTABLE" webp
upload_set "image/x-icon"          "$CACHE_IMMUTABLE" ico
upload_set "font/woff2"            "$CACHE_IMMUTABLE" woff2
upload_set "font/woff"             "$CACHE_IMMUTABLE" woff
upload_set "font/ttf"              "$CACHE_IMMUTABLE" ttf
upload_set "font/otf"              "$CACHE_IMMUTABLE" otf
upload_set "application/pdf"       "$CACHE_IMMUTABLE" pdf
upload_set "text/plain"            "$CACHE_IMMUTABLE" txt csv
upload_set "application/xml"       "$CACHE_IMMUTABLE" xml

# 2) Upload HTML last (short cache so updates take effect immediately)
upload_set "text/html; charset=utf-8" "$CACHE_HTML" html htm

# 3) Fallback: anything not matched above (keeps AWS default detection)
#    You can comment this out if you want to strictly control all types.
echo "→ Syncing remaining files (fallback, AWS mime guess)"
aws s3 sync . "s3://$BUCKET/" \
  --only-show-errors \
  "${EXCLUDES[@]}" \
  --exclude "*" \
  --include "*.*" \
  --delete

# 4) Special fixed-URL overrides (uploaded LAST so metadata wins)

# robots.txt (short cache)
upload_exact "robots.txt" "text/plain; charset=utf-8" "$CACHE_ROBOTS"

# favicon.ico (long cache)
upload_exact "favicon.ico" "image/x-icon" "$CACHE_FAVICON"

## Sitemaps (moderate cache)
#upload_exact "sitemap.xml" "application/xml; charset=utf-8" "$CACHE_SITEMAP"
#upload_exact "sitemap_index.xml" "application/xml; charset=utf-8" "$CACHE_SITEMAP"
#
## Service workers (no-cache; ensure browsers revalidate)
#upload_exact "sw.js" "text/javascript; charset=utf-8" "$CACHE_SW"
#upload_exact "service-worker.js" "text/javascript; charset=utf-8" "$CACHE_SW"
#
## Web App Manifest (short cache if not versioned)
#upload_exact "manifest.json" "application/manifest+json; charset=utf-8" "$CACHE_MANIFEST"
#upload_exact "site.webmanifest" "application/manifest+json; charset=utf-8" "$CACHE_MANIFEST"
#
## App/site association files (JSON, usually without extensions)
#upload_exact "apple-app-site-association" "application/json; charset=utf-8" "$CACHE_AASA"
#upload_exact ".well-known/apple-app-site-association" "application/json; charset=utf-8" "$CACHE_AASA"
#upload_exact ".well-known/assetlinks.json" "application/json; charset=utf-8" "$CACHE_AASA"
#
## security.txt (RFC 9116) — try well-known first
#upload_exact ".well-known/security.txt" "text/plain; charset=utf-8" "$CACHE_SECURITY"
#upload_exact "security.txt" "text/plain; charset=utf-8" "$CACHE_SECURITY"
#
## Optional: touch common Apple touch icons (you may change cache policy if you expect frequent updates)
#upload_exact "apple-touch-icon.png" "image/png" "$CACHE_FAVICON"
#upload_exact "apple-touch-icon-precomposed.png" "image/png" "$CACHE_FAVICON"

# 5) Optional CloudFront invalidation
if [[ -n "$CF_DIST_ID" ]]; then
  echo "→ Creating CloudFront invalidation /* for distribution $CF_DIST_ID"
  aws cloudfront create-invalidation \
    --distribution-id "$CF_DIST_ID" \
    --paths "/*" \
    --output text --query 'Invalidation.Id' \
  | xargs -I{} echo "   Invalidation ID: {}"
else
  echo "Tip: pass your CloudFront Distribution ID as the second argument to invalidate caches."
fi

echo "✅ Deploy complete."