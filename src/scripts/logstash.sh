#! /bin/bash
set -e  # Exit on error

echo "=== LOGSTASH INSTALLATION SCRIPT ==="

# Download GPG-KEY-elasticsearchk 
sudo apt update -y
echo ">>> Downloading Elasticsearch GPG key..."
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg

if [ ! -f /usr/share/keyrings/elastic-keyring.gpg ]; then
    echo "ERROR: Failed to download GPG key"
    exit 1
fi
echo "GPG key installed successfully"

# Install prerequisites
echo ">>> Updating apt and installing prerequisites..."
sudo apt-get update -y
sudo apt-get install apt-transport-https -y

# Install and check Elastic repository
REPO_LINE="deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main"
REPO_FILE="/etc/apt/sources.list.d/elastic-8.x.list"

if [ -f "$REPO_FILE" ] && grep -qF "$REPO_LINE" "$REPO_FILE"; then
    echo "Elastic repository đã tồn tại, bỏ qua bước thêm repository"
else
    echo ">>> Thêm Elastic repository..."
    echo "$REPO_LINE" | sudo tee "$REPO_FILE"
    echo "Elastic repository đã được thêm"
fi

# Update and install logstash
echo ">>> Installing Logstash..."
sudo apt-get update -y
sudo apt-get install logstash -y

# Create folder for system drop
echo ">>> Creating systemd drop-in directory..."
sudo mkdir -p /etc/systemd/system/logstash.service.d

# Create file AWS credentials
echo ">>> Creating AWS credentials file..."
sudo tee /etc/systemd/system/logstash.service.d/aws-keys.conf > /dev/null <<'EOF'
[Service]
Environment="AWS_ACCESS_KEY=<key>"
Environment="AWS_SECRET_KEY=<secret>"
EOF
echo "AWS credentials configured"

# configured logstash
echo ">>> Creating Logstash configuration..."
sudo tee /etc/logstash/conf.d/gitlab_winlog.conf > /dev/null <<'EOF'
input {
  beats {
    port => 5044
  }
}

filter {
  if [service] == "gitlab" {
    # Rails logs 
    if "gitlab_auth" in [tags] {
      if [meta][remote_ip] {
        mutate {
          rename => { "[meta][remote_ip]" => "[source][ip]" }
        }
      }
      if [remote_ip] {
        mutate {
          rename => { "remote_ip" => "client_ip" }
        }
      }
      mutate {
        rename => {
          "ua" => "user_agent"
          "action" => "[event][action]"
          "controller" => "[event][controller]"
          "method" => "http.method"
          "path" => "http.path"
          "status" => "http.status"
        }
        convert => { "http.status" => "integer" }
      }
    }
    # Nginx logs 
    else if [log_type] == "nginx_access" {
      mutate {
        rename => {
          "[nginx][remote_addr]" => "[source][ip]"
          "[nginx][method]" => "[http][method]"
          "[nginx][url]" => "[http][path]"
          "[nginx][status]" => "[http][status_code]"
          "[nginx][user_agent]" => "[user_agent][original]"
          "[nginx][referrer]" => "[http][referrer]"
          "[nginx][body_bytes]" => "[http][response][bytes]"
          "[nginx][ssl_verify]" => "[tls][established]"
          "[nginx][ssl_subject]" => "[tls][client][subject]"
          "[nginx][ssl_issuer]" => "[tls][client][issuer]"
        }
      }
      # Convert SSL_VERIFY to boolean
      if [tls][established] == "SUCCESS" {
        mutate {
          replace => { "[tls][established]" => "true" }
        }
      } else if [tls][established] == "NONE" {
        mutate {
          replace => { "[tls][established]" => "false" }
        }
      }
    }
  }
}

output {
  # Output gitlab auth logs
  if "gitlab_auth" in [tags] {
    elasticsearch {
      hosts => ["http://192.168.20.161:9200"]
      index => "gitlab-auth-%{+YYYY.MM.dd}"
      user => "elastic"
      password => "<password>"
    }
  } else {
    # Output logs 
    elasticsearch {
      hosts => ["http://192.168.20.161:9200"]
      index => "logs-%{+YYYY.MM.dd}"
      user => "elastic"
      password => "<password>"
    }
  }
  
  # Backup logs to S3
  s3 {
    access_key_id => "${AWS_ACCESS_KEY}"
    secret_access_key => "${AWS_SECRET_KEY}"
    region => "ap-southeast-1"
    bucket => "zt-devsecops-logs"
    codec => json_lines
    encoding => "gzip"
    prefix => "logs/%{+YYYY/MM/dd}/"
    size_file => 10485760
    time_file => 1
    canned_acl => "private"
    storage_class => "STANDARD"
  }
  
  # Debug output
  stdout { codec => rubydebug }
}
EOF
echo " Configuration file created at /etc/logstash/conf.d/gitlab_winlog.conf"

# Reload systemd và enable service
echo ">>> Configuring Logstash service..."
sudo systemctl daemon-reload
sudo systemctl enable logstash.service

# Start Logstash service
echo ">>> Starting Logstash service..."
sudo systemctl start logstash.service

# Check status
sleep 3
if sudo systemctl is-active --quiet logstash.service; then
    echo "Logstash service is running"
    sudo systemctl status logstash.service --no-pager
else
    echo "WARNING: Logstash service is not running"
    echo "Check logs with: sudo journalctl -u logstash.service -n 50"
    sudo systemctl status logstash.service --no-pager
fi

echo ""
echo "=== INSTALLATION COMPLETED ==="
echo "Configuration file: /etc/logstash/conf.d/gitlab_winlog.conf"
echo "Service status: sudo systemctl status logstash"
# echo "View logs: sudo journalctl -u logstash -f"

