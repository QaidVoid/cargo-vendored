#!/bin/bash

# Script to check for updates and vendor dependencies

# Set up environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGES_UPDATED=false

# Source helper functions
source "$SCRIPT_DIR/utils.sh"

# Run main function
main() {
    # Load package list
    local packages=$(cat "$ROOT_DIR/packages.json")
    local num_packages=$(echo "$packages" | jq length)
    
    # Create cache file if it doesn't exist
    if [ ! -f "$ROOT_DIR/versions_cache.json" ]; then
        echo "{}" > "$ROOT_DIR/versions_cache.json"
    fi
    
    # Load cache
    local cache=$(cat "$ROOT_DIR/versions_cache.json")
    
    # Create new cache
    local new_cache="{}"
    
    # Process each package
    for (( i=0; i<$num_packages; i++ )); do
        local name=$(echo "$packages" | jq -r ".[$i].name")
        local repo=$(echo "$packages" | jq -r ".[$i].repo")
        local tag_pattern=$(echo "$packages" | jq -r ".[$i].tag // \"\"")
        
        log_info "Processing $name ($repo)..."
        
        # Get cached version
        local cached_version=$(echo "$cache" | jq -r ".[\"$name\"].version // \"\"")
        
        # Get latest version from GitHub
        local version_info=$(get_latest_version "$repo" "$tag_pattern")
        local latest_version=$(echo "$version_info" | cut -d'|' -f1)
        local tarball_url=$(echo "$version_info" | cut -d'|' -f2)
        
        # Check if update is needed
        if [ "$latest_version" == "$cached_version" ] && [ "$cached_version" != "" ]; then
            log_info "  Using cached version: $cached_version"
            local package_data=$(echo "$cache" | jq ".\"$name\"")
            new_cache=$(echo "$new_cache" | jq ". + {\"$name\": $package_data}")
        else
            log_info "  Found new version: $latest_version"
            PACKAGES_UPDATED=true
            
            # Process package
            if process_package "$name" "$repo" "$latest_version" "$tarball_url"; then
                # Add to new cache
                local timestamp=$(date +%s)
                local clean_version=$(echo "$latest_version" | sed 's/^v//')
                local release_version="v${clean_version}-${name}"
                
                new_cache=$(echo "$new_cache" | jq ". + {\"$name\": {\"version\": \"$latest_version\", \"repo\": \"$repo\", \"last_checked\": $timestamp, \"published_version\": \"$release_version\"}}")
            else
                log_error "  Failed to process package. Keeping old cache entry if available."
                
                # Keep old cache entry if available
                if [ "$cached_version" != "" ]; then
                    local package_data=$(echo "$cache" | jq ".\"$name\"")
                    new_cache=$(echo "$new_cache" | jq ". + {\"$name\": $package_data}")
                else
                    local timestamp=$(date +%s)
                    new_cache=$(echo "$new_cache" | jq ". + {\"$name\": {\"version\": \"$latest_version\", \"repo\": \"$repo\", \"last_checked\": $timestamp, \"error\": true}}")
                fi
            fi
        fi
    done
    
    # Save new cache
    echo "$new_cache" | jq '.' > "$ROOT_DIR/versions_cache.json"
    log_info "Updated cache saved to versions_cache.json"
    
    # Set output variable for GitHub Actions
    if [ "$PACKAGES_UPDATED" = true ]; then
        echo "PACKAGES_UPDATED=true" >> $GITHUB_ENV
        log_info "Updates found. Setting PACKAGES_UPDATED=true"
    else
        echo "PACKAGES_UPDATED=false" >> $GITHUB_ENV
        log_info "No updates found. Setting PACKAGES_UPDATED=false" 
    fi
}

# Run main function
main
