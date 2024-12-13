#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Get current timestamp for the report filename
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="vps-audit-report-${TIMESTAMP}.txt"

# Function to check and report with three states
check_security() {
    local test_name="$1"
    local status="$2"
    local message="$3"
    
    case $status in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[PASS] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[WARN] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[FAIL] $test_name - $message" >> "$REPORT_FILE"
            ;;
    esac
    echo "" >> "$REPORT_FILE"
}

echo "Starting VPS audit..."
echo "VPS Audit Report - $(date)" > "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Check system uptime
UPTIME=$(uptime -p)
UPTIME_SINCE=$(uptime -s)
echo -e "\nSystem Uptime Information:" >> "$REPORT_FILE"
echo "Current uptime: $UPTIME" >> "$REPORT_FILE"
echo "System up since: $UPTIME_SINCE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo -e "System Uptime: $UPTIME (since $UPTIME_SINCE)"

# Check if system requires restart
if [ -f /var/run/reboot-required ]; then
    check_security "System Restart" "WARN" "System requires a restart to apply updates"
else
    check_security "System Restart" "PASS" "No restart required"
fi

# Check SSH root login
if grep -q "^PermitRootLogin.*no" /etc/ssh/sshd_config; then
    check_security "SSH Root Login" "PASS" "Root login is properly disabled in SSH configuration"
else
    check_security "SSH Root Login" "FAIL" "Root login is currently allowed - this is a security risk. Disable it in /etc/ssh/sshd_config"
fi

# Check SSH password authentication
if grep -q "^PasswordAuthentication.*no" /etc/ssh/sshd_config; then
    check_security "SSH Password Auth" "PASS" "Password authentication is disabled, key-based auth only"
else
    check_security "SSH Password Auth" "FAIL" "Password authentication is enabled - consider using key-based authentication only"
fi

# Check SSH default port
SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config | awk '{print $2}')
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi
if [ "$SSH_PORT" = "22" ]; then
    check_security "SSH Port" "WARN" "Using default port 22 - consider changing to a non-standard port for security by obscurity"
else
    check_security "SSH Port" "PASS" "Using non-default port $SSH_PORT which helps prevent automated attacks"
fi

# Check UFW status
if ufw status | grep -q "active"; then
    check_security "Firewall Status" "PASS" "UFW firewall is active and protecting your system"
else
    check_security "Firewall Status" "FAIL" "UFW firewall is not active - your system is exposed to network attacks"
fi

# Check for unattended upgrades
if dpkg -l | grep -q "unattended-upgrades"; then
    check_security "Unattended Upgrades" "PASS" "Automatic security updates are configured"
else
    check_security "Unattended Upgrades" "FAIL" "Automatic security updates are not configured - system may miss critical updates"
fi

# Check fail2ban
if dpkg -l | grep -q "fail2ban"; then
    if systemctl is-active fail2ban >/dev/null 2>&1; then
        check_security "Fail2ban" "PASS" "Brute force protection is active and running"
    else
        check_security "Fail2ban" "WARN" "Fail2ban is installed but not running - brute force protection is disabled"
    fi
else
    check_security "Fail2ban" "FAIL" "No brute force protection installed - system is vulnerable to login attacks"
fi

# Check failed login attempts
FAILED_LOGINS=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
if [ "$FAILED_LOGINS" -lt 10 ]; then
    check_security "Failed Logins" "PASS" "Only $FAILED_LOGINS failed login attempts detected - this is within normal range"
elif [ "$FAILED_LOGINS" -lt 50 ]; then
    check_security "Failed Logins" "WARN" "$FAILED_LOGINS failed login attempts detected - might indicate breach attempts"
else
    check_security "Failed Logins" "FAIL" "$FAILED_LOGINS failed login attempts detected - possible brute force attack in progress"
fi

# Check system updates
UPDATES=$(apt-get -s upgrade 2>/dev/null | grep -P '^\d+ upgraded' | cut -d" " -f1)
if [ "$UPDATES" -eq 0 ]; then
    check_security "System Updates" "PASS" "All system packages are up to date"
else
    check_security "System Updates" "FAIL" "$UPDATES security updates available - system is vulnerable to known exploits"
fi

# Check running services
SERVICES=$(systemctl list-units --type=service --state=running | grep "loaded active running" | wc -l)
if [ "$SERVICES" -lt 20 ]; then
    check_security "Running Services" "PASS" "Running minimal services ($SERVICES) - good for security"
elif [ "$SERVICES" -lt 40 ]; then
    check_security "Running Services" "WARN" "$SERVICES services running - consider reducing attack surface"
else
    check_security "Running Services" "FAIL" "Too many services running ($SERVICES) - increases attack surface"
fi

# Check active internet connections
CONNECTIONS=$(netstat -tuln | grep LISTEN | wc -l)
if [ "$CONNECTIONS" -lt 10 ]; then
    check_security "Open Ports" "PASS" "Minimal ports open ($CONNECTIONS) - good security posture"
elif [ "$CONNECTIONS" -lt 20 ]; then
    check_security "Open Ports" "WARN" "$CONNECTIONS ports open - consider closing unnecessary ports"
else
    check_security "Open Ports" "FAIL" "Too many open ports ($CONNECTIONS) - significant attack surface"
fi

# Check disk space usage
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print int($5)}')
if [ "$DISK_USAGE" -lt 50 ]; then
    check_security "Disk Usage" "PASS" "Healthy disk space available (${DISK_USAGE}% used - Used: ${DISK_USED} of ${DISK_TOTAL}, Available: ${DISK_AVAIL})"
elif [ "$DISK_USAGE" -lt 80 ]; then
    check_security "Disk Usage" "WARN" "Disk space usage is moderate (${DISK_USAGE}% used - Used: ${DISK_USED} of ${DISK_TOTAL}, Available: ${DISK_AVAIL})"
else
    check_security "Disk Usage" "FAIL" "Critical disk space usage (${DISK_USAGE}% used - Used: ${DISK_USED} of ${DISK_TOTAL}, Available: ${DISK_AVAIL})"
fi

# Check memory usage
MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')
MEM_AVAIL=$(free -h | awk '/^Mem:/ {print $7}')
MEM_USAGE=$(free | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
if [ "$MEM_USAGE" -lt 50 ]; then
    check_security "Memory Usage" "PASS" "Healthy memory usage (${MEM_USAGE}% used - Used: ${MEM_USED} of ${MEM_TOTAL}, Available: ${MEM_AVAIL})"
elif [ "$MEM_USAGE" -lt 80 ]; then
    check_security "Memory Usage" "WARN" "Moderate memory usage (${MEM_USAGE}% used - Used: ${MEM_USED} of ${MEM_TOTAL}, Available: ${MEM_AVAIL})"
else
    check_security "Memory Usage" "FAIL" "Critical memory usage (${MEM_USAGE}% used - Used: ${MEM_USED} of ${MEM_TOTAL}, Available: ${MEM_AVAIL})"
fi

# Check CPU usage
CPU_CORES=$(nproc)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print int($2)}')
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print int($8)}')
CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | awk -F',' '{ print $1 }' | tr -d ' ')
if [ "$CPU_USAGE" -lt 50 ]; then
    check_security "CPU Usage" "PASS" "Healthy CPU usage (${CPU_USAGE}% used - Active: ${CPU_USAGE}%, Idle: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Cores: ${CPU_CORES})"
elif [ "$CPU_USAGE" -lt 80 ]; then
    check_security "CPU Usage" "WARN" "Moderate CPU usage (${CPU_USAGE}% used - Active: ${CPU_USAGE}%, Idle: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Cores: ${CPU_CORES})"
else
    check_security "CPU Usage" "FAIL" "Critical CPU usage (${CPU_USAGE}% used - Active: ${CPU_USAGE}%, Idle: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Cores: ${CPU_CORES})"
fi

# Check sudo configuration
if grep -q "^Defaults.*logfile" /etc/sudoers; then
    check_security "Sudo Logging" "PASS" "Sudo commands are being logged for audit purposes"
else
    check_security "Sudo Logging" "FAIL" "Sudo commands are not being logged - reduces audit capability"
fi

# Check password policy
if [ -f "/etc/security/pwquality.conf" ]; then
    if grep -q "minlen.*12" /etc/security/pwquality.conf; then
        check_security "Password Policy" "PASS" "Strong password policy is enforced"
    else
        check_security "Password Policy" "FAIL" "Weak password policy - passwords may be too simple"
    fi
else
    check_security "Password Policy" "FAIL" "No password policy configured - system accepts weak passwords"
fi

# Check for suspicious SUID files
SUID_FILES=$(find / -type f -perm -4000 2>/dev/null | grep -v -e '^/usr/bin' -e '^/bin' -e '^/sbin' | wc -l)
if [ "$SUID_FILES" -eq 0 ]; then
    check_security "SUID Files" "PASS" "No suspicious SUID files found - good security practice"
else
    check_security "SUID Files" "FAIL" "Found $SUID_FILES suspicious SUID files - potential privilege escalation risk"
fi

# Add system information summary to report
echo "================================" >> "$REPORT_FILE"
echo "System Information Summary:" >> "$REPORT_FILE"
echo "Hostname: $(hostname)" >> "$REPORT_FILE"
echo "Kernel: $(uname -r)" >> "$REPORT_FILE"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)" >> "$REPORT_FILE"
echo "CPU Cores: $(nproc)" >> "$REPORT_FILE"
echo "Total Memory: $(free -h | awk '/^Mem:/ {print $2}')" >> "$REPORT_FILE"
echo "Total Disk Space: $(df -h / | awk 'NR==2 {print $2}')" >> "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"

echo -e "\nVPS audit complete. Full report saved to $REPORT_FILE"
echo -e "Review $REPORT_FILE for detailed recommendations."

# Add summary to report
echo "================================" >> "$REPORT_FILE"
echo "End of VPS Audit Report" >> "$REPORT_FILE"
echo "Please review all failed checks and implement the recommended fixes." >> "$REPORT_FILE"