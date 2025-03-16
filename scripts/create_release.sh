#!/bin/bash

# Script to create GitHub releases for updated packages

# Set up environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$ROOT_DIR/releases"

# Source helper functions
source "$SCRIPT_DIR/utils.sh"

# Main function
main() {
    # Load cache
    local cache=$(cat "$ROOT_DIR/versions_cache.json")
    
    # Check if we have any packages to release
    if [ ! -f "$ROOT_DIR/versions_cache.json" ]; then
        log_error "No cache file found. Nothing to release."
        exit 1
    fi
    
    # Get list of packages from cache
    local packages=$(echo "$cache" | jq -r 'keys[]')
    
    # Process each package
    for name in $packages; do
        # Get package info
        local version=$(echo "$cache" | jq -r ".\"$name\".version")
        local published_version=$(echo "$cache" | jq -r ".\"$name\".published_version // \"\"")
        local error=$(echo "$cache" | jq -r ".\"$name\".error // false")
        
        # Skip packages with errors
        if [ "$error" == "true" ]; then
            log_info "Skipping $name due to previous errors"
            continue
        fi
        
        # Skip packages without a published version
        if [ -z "$published_version" ] || [ "$published_version" == "null" ]; then
            log_info "Skipping $name as it was not prepared for release"
            continue
        fi
        
        # Clean version without 'v' prefix
        local clean_version=$(echo "$version" | sed 's/^v//')
        
        # Check if release archive exists
        local release_archive="$RELEASE_DIR/${name}-${clean_version}-vendored-dependencies.tar.xz"
        if [ ! -f "$release_archive" ]; then
            log_error "Release archive for $name not found: $release_archive"
            continue
        fi
        
        # Create GitHub release
        gh release create "$published_version" \
          --title "$published_version" \
          --notes "Automatic release of vendored dependencies for $name version $version" \
          "$release_archive"

        if [ $? -eq 0 ]; then
          echo "Successfully created GitHub release for $NAME"
        else
          echo "Failed to create GitHub release for $NAME"
        fi
    done
}

# Run main function
main
