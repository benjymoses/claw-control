#!/bin/bash
# Homebrew wrapper to automatically track installed packages

brew() {
  command brew "$@"
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    local pkg_file="/home/node/.openclaw/homebrew/packages.txt"
    mkdir -p "$(dirname "$pkg_file")"
    
    # Handle install
    if [ "$1" = "install" ]; then
      # Save each package that was installed (skip flags starting with -)
      for pkg in "${@:2}"; do
        [[ "$pkg" =~ ^- ]] && continue  # Skip flags like --verbose
        if ! grep -qx "$pkg" "$pkg_file" 2>/dev/null; then
          echo "$pkg" >> "$pkg_file"
        fi
      done
    fi
    
    # Handle uninstall/remove/rm
    if [ "$1" = "uninstall" ] || [ "$1" = "remove" ] || [ "$1" = "rm" ]; then
      # Remove each package from the list (skip flags starting with -)
      for pkg in "${@:2}"; do
        [[ "$pkg" =~ ^- ]] && continue  # Skip flags
        if [ -f "$pkg_file" ]; then
          # Use grep to filter out the package (Linux container, no macOS sed issues)
          grep -vx "$pkg" "$pkg_file" > "${pkg_file}.tmp" 2>/dev/null || true
          mv "${pkg_file}.tmp" "$pkg_file" 2>/dev/null || true
        fi
      done
    fi
  fi
  
  return $exit_code
}
