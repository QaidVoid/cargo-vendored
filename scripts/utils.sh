#!/bin/bash

# Shared utility functions for package scripts

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="$ROOT_DIR/downloads"
VENDOR_DIR="$ROOT_DIR/vendor"
RELEASE_DIR="$ROOT_DIR/releases"
GITHUB_API="https://api.github.com"

# Create directories if they don't exist
mkdir -p "$DOWNLOAD_DIR" "$VENDOR_DIR" "$RELEASE_DIR"

# Logging functions
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

log_success() {
    echo "[SUCCESS] $1"
}

# Function to get latest version from GitHub
get_latest_version() {
    local repo=$1
    local tag_pattern=$2
    local url="$GITHUB_API/repos/$repo/releases"
    
    # Get all releases
    local releases=$(curl -s "$url")
    
    # Check if rate limit exceeded
    if echo "$releases" | grep -q "API rate limit exceeded"; then
        log_error "GitHub API rate limit exceeded. Try again later."
        exit 1
    fi
    
    # Filter by tag pattern if provided
    if [ -n "$tag_pattern" ]; then
        # Replace * with .* for regex pattern
        local regex_pattern=$(echo "$tag_pattern" | sed 's/\*/.*/g')
        # Get the latest tag that matches the pattern
        local latest_tag=$(echo "$releases" | jq -r "[.[] | select(.tag_name | test(\"$regex_pattern\")) | select(.prerelease == false)] | sort_by(.published_at) | reverse | .[0].tag_name")
        # Get the tarball URL for the latest tag
        local tarball_url=$(echo "$releases" | jq -r "[.[] | select(.tag_name | test(\"$regex_pattern\")) | select(.prerelease == false)] | sort_by(.published_at) | reverse | .[0].tarball_url")
    else
        # Get the latest tag
        local latest_tag=$(echo "$releases" | jq -r "[.[] | select(.prerelease == false)] | .[0].tag_name")
        # Get the tarball URL for the latest tag
        local tarball_url=$(echo "$releases" | jq -r "[.[] | select(.prerelease == false)] | .[0].tarball_url")
    fi
    
    # If no tag found, try to get default branch
    if [ "$latest_tag" == "null" ] || [ -z "$latest_tag" ]; then
        local default_branch=$(curl -s "$GITHUB_API/repos/$repo" | jq -r ".default_branch")
        if [ "$default_branch" != "null" ]; then
            latest_tag="$default_branch"
            tarball_url="https://github.com/$repo/archive/$default_branch.tar.gz"
        else
            latest_tag="unknown"
            tarball_url=""
        fi
    fi
    
    echo "$latest_tag|$tarball_url"
}

# Function to download and extract a package
download_package() {
    local name=$1
    local tarball_url=$2
    local version=$3
    local download_path="$DOWNLOAD_DIR/$name-$version.tar.gz"
    local extract_path="$DOWNLOAD_DIR/$name-$version"
    
    log_info "Downloading $name ($version)..."
    
    # Remove existing download if it exists
    if [ -f "$download_path" ]; then
        rm -f "$download_path"
    fi
    
    # Remove existing extract directory if it exists
    if [ -d "$extract_path" ]; then
        rm -rf "$extract_path"
    fi
    
    # Download the tarball
    curl -s -L "$tarball_url" -o "$download_path"
    
    # Check if download was successful
    if [ $? -ne 0 ] || [ ! -f "$download_path" ]; then
        log_error "Failed to download package."
        return 1
    fi
    
    # Create extract directory
    mkdir -p "$extract_path"
    
    # Extract the tarball
    tar -xzf "$download_path" -C "$extract_path" --strip-components 1
    
    # Check if extraction was successful
    if [ $? -ne 0 ]; then
        log_error "Failed to extract package."
        return 1
    fi
    
    log_success "Successfully downloaded and extracted $name ($version)"
    return 0
}

# Function to vendor dependencies
vendor_dependencies() {
    local name=$1
    local version=$2
    local package_dir="$DOWNLOAD_DIR/$name-$version"
    local vendor_path="$VENDOR_DIR/$name-$version"
    
    log_info "Vendoring dependencies for $name ($version)..."
    
    # Check if Cargo.toml exists
    if [ ! -f "$package_dir/Cargo.toml" ]; then
        log_error "No Cargo.toml found in package directory."
        return 1
    fi
    
    # Remove existing vendor directory if it exists
    if [ -d "$vendor_path" ]; then
        rm -rf "$vendor_path"
    fi
    
    # Create vendor directory
    mkdir -p "$vendor_path"
    
    # Run cargo vendor
    (cd "$package_dir" && cargo vendor --versioned-dirs "$vendor_path")
    
    # Check if cargo vendor was successful
    if [ $? -ne 0 ]; then
        log_error "Failed to vendor dependencies."
        return 1
    fi
    
    log_success "Successfully vendored dependencies for $name"
    return 0
}

# Function to prepare a release
prepare_release() {
    local name=$1
    local version=$2
    local package_dir="$DOWNLOAD_DIR/$name-$version"
    local release_dir="$RELEASE_DIR/$name"
    local vendor_path="$VENDOR_DIR/$name-$version"
    
    # Extract the version number without 'v' prefix if present
    local clean_version=$(echo "$version" | sed 's/^v//')
    
    # Create the release version (format: {name}-{clean_version})
    local release_version="${name}-${clean_version}"
    
    log_info "Preparing release for $name as $release_version..."

    # Check if vendor directory exists
    if [ ! -d "$vendor_path" ]; then
        log_error "Vendor directory not found: $vendor_path"
        return 1
    fi
    
    # Remove existing release directory if it exists
    if [ -d "$release_dir" ]; then
        rm -rf "$release_dir"
    fi
    
    # Create release directory
    mkdir -p "$release_dir"
    
    # Copy the VENDORED dependencies to the release directory (not the package itself)
    cp -r "$vendor_path/"* "$release_dir/"
    
    # Create a release archive
    local release_archive="$RELEASE_DIR/${release_version}-vendored-dependencies.tar.xz"
    (cd "$RELEASE_DIR" && tar --transform "s|^$name|vendor|" -cJf "$release_archive" "$name")
    
    log_success "Prepared release archive of vendored dependencies: $release_archive"
    return 0
}

# Function to process a package (download, vendor, prepare release)
process_package() {
    local name=$1
    local repo=$2
    local version=$3
    local tarball_url=$4
    
    # Download the package
    if ! download_package "$name" "$tarball_url" "$version"; then
        log_error "Failed to download package $name"
        return 1
    fi
    
    # Vendor dependencies
    if ! vendor_dependencies "$name" "$version"; then
        log_error "Failed to vendor dependencies for $name"
        return 1
    fi
    
    # Prepare release
    if ! prepare_release "$name" "$version"; then
        log_error "Failed to prepare release for $name"
        return 1
    fi
    
    log_success "Successfully processed package $name"
    return 0
}
