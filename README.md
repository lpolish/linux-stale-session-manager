# Linux Stale Session Manager

[![Checksum Verification](https://github.com/lpolish/linux-stale-session-manager/actions/workflows/update-checksums.yml/badge.svg)](https://github.com/lpolish/linux-stale-session-manager/actions)

## Description

Enterprise-grade solution for managing stale user sessions on Linux servers with cryptographic verification and enhanced security.

## Key features

- Interactive terminal menu system
- Configurable idle thresholds (1m-9999m)
- User whitelist protection
- Multiple termination methods (SIGTERM/SIGKILL)
- Email/Slack notifications
- Dry-run mode for testing 
- Comprehensive audit logging
- Systemd/cron integration
- Cryptographic integrity verification (NEW)

## Installation methods

### Secure (recommended) installation

```
# run with --verify to ensure checksums are good
curl -fsSL https://raw.githubusercontent.com/lpolish/linux-stale-session-manager/refs/heads/main/install.sh | sudo bash -s -- --verify
```

### Manual installation

```
wget https://raw.githubusercontent.com/lpolish/linux-stale-session-manager/refs/heads/main/{install.sh,checksums.sha256}
sha256sum -c checksums.sha256 --ignore-missing
chmod +x install.sh
sudo ./install.sh --verify
```

### Legacy install (no checksum verification)

```
curl -sSL https://raw.githubusercontent.com/lpolish/linux-stale-session-manager/refs/heads/main/install.sh | sudo bash
```

## Uninstall

```
sudo stale-session-manager --uninstall
```
or

```
sudo bash install.sh --uninstall
```

## Security enhancements (v2.2)

- SHA-256 checksum verification
- Download integrity checking
- Secure temp file handling
- Privilege separation
- Audit logging

## Configuration

Primary config file:

```
/etc/stale_session_manager.conf
```

Configuration options:

```
MAX_IDLE_MINUTES=120
WHITELIST=(root admin)
NOTIFY_ADMIN=true/false
ADMIN_EMAIL="your@email"
LOG_LEVEL="verbose" (NEW)
```

## Automation Options

1. **systemd** (Recommended):

```
sudo systemctl enable stale-session-cleaner.timer  # Daily at 3AM
```

2. **Cron**:

```
0 3 * * * /usr/local/bin/stale-session-manager --idle 60 --notify
```

3. **Manual run**:

```
sudo stale-session-manager --idle 30 --whitelist "admin,backup"
```

## Usage examples

**Interactive Mode**:

```
sudo stale-session-manager
```

**Quick Clean**:

```
sudo stale-session-manager --idle 120 --force
```

**Dry Run**:

```
sudo stale-session-manager --dry-run --idle 60
```

## File Locations

```
/usr/local/bin/stale-session-manager
/etc/stale_session_manager.conf
/var/log/stale_session_manager.log
/etc/systemd/system/stale-session-cleaner.service
```

## Logging
All activities are logged with timestamps:

```
[2025-05-15 03:00:01] Terminated user 'jdoe' on pts/3 (idle: 125 minutes)
```

## Troubleshooting
**Q**: Checksum verification fails?
**A**: Run:

```
curl -fsSL https://raw.githubusercontent.com/lpolish/linux-stale-session-manager/main/install.sh | sudo bash -- --verify
```

**Q**: Email notifications not working?
**A**: Verify mailutils is installed and check:

```
/var/log/mail.log
```

## Version info

**Version**: 2.2 (2025-04-30)

**Changes**:

- Added cryptographic verification
- Enhanced security controls
- Improved logging
- Configurable log levels

**Author**: Luis Pulido Diaz

**License**: MIT

**Issues**: https://github.com/lpolish/linux-stale-session-manager/issues 
