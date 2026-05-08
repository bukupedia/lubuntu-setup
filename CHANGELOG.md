# Changelog - lubuntu-setup.sh

All notable changes to this script will be documented in this file.

## [1.1.0] - 2026-05-08

### Changed

- **Error Handling**: Removed ERR trap that could cause cascading failures. Replaced with explicit error handling using `run_or_fail()` helper.
- **Package Installation**:
  - Removed invalid package `lxsession` (bundled with lxde-core)
  - Replaced deprecated `xorgxrdp` with `xrdp` and `xorgxrdp-generic`
- **User Detection**: Changed from insecure `eval echo "~${REAL_USER}"` to `getent passwd`
- **Root Check**: Changed `$EUID` to `$(id -u)` for portability
- **Swap Configuration**:
  - Added explicit error verification after fallocate/dd, mkswap, and swapon
  - Fixed grep pattern from `/swapfile` to `^/swapfile` (anchored, prevents false positives)
  - Added verification that swap is active before updating fstab
- **Download**: Added wget exit code verification
- **Service Management**: Added `disable_service()` helper with unit existence checks
- **Backup System**: Changed from overwriting `.bak` to timestamp-based versioning
- **Group Membership**: Added check to prevent duplicate ssl-cert group additions
- **Cleanup**: Removed risky `autoremove` (only kept autoclean)
- **Permissions**: Added `chmod 600` for .xsession file

### Added

- `run_or_fail()` helper function with exit code tracking
- `disable_service()` helper function for safer service management
- Timestamped backups: `{file}.bak_YYYYMMDD_HHMS`
- Explicit exit on critical failures with descriptive error messages
- Progress indicator for dd swap creation

### Security

- Removed `eval` usage for home directory resolution (prevents injection)
- Added explicit exit code verification for downloads

## [1.0.0] - 2026-05-08

### Added

- Initial release of Ubuntu 22.04 XRDP + LXDE provisioning script
- LXDE desktop environment installation
- XRDP with sound redirection via C-Nergy installer
- Swap file configuration (2GB)
- Polkit configuration for color management
- User configuration for ssl-cert group