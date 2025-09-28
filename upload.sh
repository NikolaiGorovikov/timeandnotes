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

# Helper to upload a set of extensions with a single metadata rule
#   upload_set "text/css" "$CACHE_IMMUTABLE" css
upload_set() {
  local content_type="$1"; shift
  local cache_control="$1"; shift
  local exts=( "$@" )

  # Base args; start with a blanket exclude
  local args=( aws s3 cp . "s3://$BUCKET/" --recursive --only-show-errors \
               --exclude "*" \
               --cache-control "$cache_control" \
               --content-type "$content_type" )

  # Narrow to desired extensions
  local had_include=false
  for ext in "${exts[@]}"; do
    args+=( --include "*.${ext}" )
    had_include=true
  done

  # Apply your common excludes *after* includes so they still win
  args+=( "${EXCLUDES[@]}" )

  if [[ "$had_include" = true ]]; then
    echo "→ Uploading: ${exts[*]} as ${content_type} (cache: $cache_control)"
    "${args[@]}"
  fi
}

echo "Deploying current directory to s3://$BUCKET ..."

# 1) Upload immutable/static assets first (long cache)
upload_set "text/css"              "$CACHE_IMMUTABLE" css
upload_set "text/javascript"       "$CACHE_IMMUTABLE" js mjs cjs
upload_set "application/json"      "$CACHE_IMMUTABLE" json webmanifest map
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

# 4) Optional CloudFront invalidation
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