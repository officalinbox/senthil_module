#!/bin/bash

# RHEL 8 Precheck Script
# Checks common prerequisites and outputs [OK] or [NOT OK]

echo "=== RHEL 8 Precheck Report (Run as root) ==="
echo "Timestamp: $(date)"
echo

# Function to print result
print_result() {
    local check_name="$1"
    local status="$2"
    local message="$3"
    if [ "$status" = "OK" ]; then
        echo "[$status] $check_name"
    else
        echo "[$status] $check_name - $message"
    fi
}

# Check 1: OS Version (must be RHEL 8)
OS_VERSION=$(cat /etc/redhat-release 2>/dev/null | grep -o '8\.[0-9]')
if [ -n "$OS_VERSION" ]; then
    print_result "OS Version" "OK"
else
    print_result "OS Version" "NOT OK" "Expected RHEL 8.x, found: $(cat /etc/redhat-release 2>/dev/null || echo 'Unknown')"
fi
echo

# Check 2: Available Disk Space on / (at least 5GB free)
DISK_FREE=$(df / | awk 'NR==2 {print $4}')
MIN_DISK=5242880  # 5GB in KB
if [ "$DISK_FREE" -ge "$MIN_DISK" ]; then
    print_result "Disk Space (/) Free" "OK"
else
    print_result "Disk Space (/) Free" "NOT OK" "$((DISK_FREE / 1024 / 1024))GB free (need 5GB+)"
fi
echo

# Check 3: Available Memory (at least 2GB free)
MEM_FREE=$(free | grep Mem: | awk '{print $4}')
MIN_MEM=2097152  # 2GB in KB
if [ "$MEM_FREE" -ge "$MIN_MEM" ]; then
    print_result "Available Memory" "OK"
else
    print_result "Available Memory" "NOT OK" "$((MEM_FREE / 1024 / 1024))GB free (need 2GB+)"
fi
echo

# Check 4: SELinux Status (enforcing or permissive)
SEL_STATUS=$(getenforce 2>/dev/null)
if [[ "$SEL_STATUS" == "Enforcing" || "$SEL_STATUS" == "Permissive" ]]; then
    print_result "SELinux Status" "OK"
else
    print_result "SELinux Status" "NOT OK" "Status: $SEL_STATUS (should be Enforcing or Permissive)"
fi
echo

# Check 5: Firewall Status (firewalld running)
if systemctl is-active --quiet firewalld; then
    print_result "Firewall (firewalld)" "OK"
else
    print_result "Firewall (firewalld)" "NOT OK" "Service not active"
fi
echo

# Summary
FAILED=0
if grep -q "NOT OK" /tmp/precheck.tmp 2>/dev/null; then
    FAILED=1
fi
if [ $FAILED -eq 0 ]; then
    echo "[OK] All checks passed!"
    exit 0
else
    echo "[NOT OK] Some checks failed. Review above."
    exit 1
fi
