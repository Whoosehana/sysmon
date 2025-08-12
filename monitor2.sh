#!/bin/bash  

EMAIL_ADMIN="h.fallahi.85@gmail.com"  
LOG_FILE="/var/log/system_monitor.log"  
REPORT_FILE="/var/log/system_report.csv"  
SERVICES=("postgresql" "apache2")  
CPU_THRESHOLD=90  
RAM_THRESHOLD=90  
DISK_THRESHOLD=90  

REQUIRED_TOOLS=("top" "free" "df" "mail" "systemctl" "awk" "grep")  
for tool in "${REQUIRED_TOOLS[@]}"; do  
    if ! command -v "$tool" &> /dev/null; then  
        echo "Error: Required tool '$tool' is not installed."  
        exit 1  
    fi  
done  

if [ ! -f "$LOG_FILE" ]; then  
    sudo touch "$LOG_FILE" || { echo "Error: cannot create $LOG_FILE"; exit 1; }  
    sudo chmod 644 "$LOG_FILE" || { echo "Error: cannot set permission for $LOG_FILE"; exit 1; }  
fi  

log_message() {  
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')  
    echo "[$timestamp] $1" | sudo tee -a "$LOG_FILE" > /dev/null || echo "Warning: Failed to write to $LOG_FILE"  
}  

send_email() {  
    local subject="$1"  
    local message="$2"  
    echo "$message" | mail -s "$subject" "$EMAIL_ADMIN" || log_message "Error: Failed to send email to $EMAIL_ADMIN"  
}  

check_cpu() {  
    local cpu_usage  
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}' | cut -d. -f1)  
    if [ -z "$cpu_usage" ]; then  
        log_message "Error: Failed to retrieve CPU usage"  
        echo "ERROR"  
        return 1  
    fi  
    if [ "$cpu_usage" -ge "$CPU_THRESHOLD" ]; then  
        log_message "ALERT: High CPU usage detected: $cpu_usage%"  
        send_email "System Alert: High CPU Usage" "CPU usage is at $cpu_usage% on $(hostname) at $(date)"  
        echo "$cpu_usage (CRITICAL)"  
    else  
        echo "$cpu_usage (OK)"  
    fi  
}  

check_ram() {  
    local ram_total ram_used ram_usage  
    ram_total=$(free -m | awk '/Mem:/ {print $2}')  
    ram_used=$(free -m | awk '/Mem:/ {print $3}')  
    if [ -z "$ram_total" ]  [ -z "$ram_used" ]  [ "$ram_total" -eq 0 ]; then  
        log_message "Error: Failed to retrieve RAM usage"  
        echo "ERROR"  
        return 1  
    fi  
    ram_usage=$((100 * ram_used / ram_total))  
    if [ "$ram_usage" -ge "$RAM_THRESHOLD" ]; then  
        log_message "ALERT: High RAM usage detected: $ram_usage%"  
        send_email "System Alert: High RAM Usage" "RAM usage is at $ram_usage% on $(hostname) at $(date)"  
        echo "$ram_usage (CRITICAL)"  
    else  
        echo "$ram_usage (OK)"  
    fi  
}  

check_disk() {  
    local disk_usage  
    disk_usage=$(df -h / | tail -1 | awk '{print $5}' | cut -d% -f1)  
    if [ -z "$disk_usage" ]; then  
        log_message "Error: Failed to retrieve Disk usage"  
        echo "ERROR"  
        return 1  
    fi  
    if [ "$disk_usage" -ge "$DISK_THRESHOLD" ]; then  
        log_message "ALERT: High Disk usage detected: $disk_usage%"  
        send_email "System Alert: High Disk Usage" "Disk usage is at $disk_usage% on $(hostname) at $(date)"  
        echo "$disk_usage (CRITICAL)"  
    else  
        echo "$disk_usage (OK)"  
    fi  
}  

check_services() {  
    local service_status="OK"  
    local service_report=""  
    for service in "${SERVICES[@]}"; do  
        if systemctl list-units --full --all | grep -q "$service.service"; then  
            if systemctl is-active --quiet "$service"; then  
                service_report="$service_report $service:RUNNING"  
            else  
                service_report="$service_report $service:DOWN"  
                service_status="CRITICAL"  
                log_message "ALERT: Service $service is down"  
                send_email "System Alert: Service Down" "Service $service is down on $(hostname) at $(date)"  
            fi  
        else  
            service_report="$service_report $service:NOT_FOUND"  
            service_status="CRITICAL"  
            log_message "Error: service $service does not exist"  
        fi  
    done  
    echo "$service_status|$service_report"  # جداکننده '|'  
}  

main() {  
    log_message "Starting system monitoring..."
    cpu_usage=$(check_cpu) || cpu_usage="ERROR"  
    ram_usage=$(check_ram) || ram_usage="ERROR"  
    disk_usage=$(check_disk) || disk_usage="ERROR"  
    service_output=$(check_services)
    service_status="${service_output%%|*}"
    service_report="${service_output#*|}"  

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')  

    echo "$timestamp,$cpu_usage,$ram_usage,$disk_usage,$service_status" | sudo tee -a "$REPORT_FILE" > /dev/null || log_message "Error: Failed to write to $REPORT_FILE"  

    echo "System Monitoring Report:"  
    echo "------------------------"  
    echo "Timestamp: $timestamp"  
    echo "CPU Usage: $cpu_usage"  
    echo "RAM Usage: $ram_usage"  
    echo "Disk Usage: $disk_usage"  
    echo "Service Status: $service_status"  
    echo "------------------------"  

    log_message "Monitoring completed"  
}  

sudo chmod 644 "$LOG_FILE" "$REPORT_FILE" || { echo "Error: Cannot set permissions"; exit 1; }  

main
