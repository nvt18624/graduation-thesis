gitlab_rails['ldap_enabled'] = true
gitlab_rails['ldap_servers'] = YAML.load <<-EOS
main:
  label: 'Active Directory'
  host: '10.0.1.4'
  port: 389
  uid: 'sAMAccountName'
  bind_dn: 'CN=Administrator,CN=Users,DC=zt,DC=devsecops,DC=local'
  password: '<password>
  encryption: 'plain'
  verify_certificates: false
  active_directory: true
  allow_username_or_email_login: true
  lowercase_usernames: false
  base: 'CN=Users,DC=zt,DC=devsecops,DC=local'
  debug: true
EOS

external_url 'https://gitlab.zt.devsecops.local'
nginx['enable'] = false

# Tell GitLab it's behind HTTPS proxy
gitlab_rails['gitlab_https'] = true
gitlab_rails['gitlab_port'] = 443
gitlab_rails['gitlab_protocol'] = 'https'
gitlab_rails['trusted_proxies'] = ['127.0.0.1']

gitlab_workhorse['listen_network'] = "tcp"
gitlab_workhorse['listen_addr'] = "127.0.0.1:8181"
gitlab_rails['extra_log_configuration'] = <<~LOG
  # LDAP authentication logs
  if defined?(Gitlab::Auth::Ldap)
    Rails.application.config.after_initialize do
      ldap_logger = Logger.new('/var/log/gitlab/gitlab-rails/ldap_auth.log')
      ldap_logger.level = Logger::DEBUG
      ldap_logger.formatter = proc do |severity, datetime, progname, msg|
        {
          timestamp: datetime.iso8601,
          severity: severity,
          source: 'ldap',
          message: msg
        }.to_json + "\n"
      end
      # Attach logger to LDAP adapter
      Gitlab::Auth::Ldap::Config.ldap_logger = ldap_logger
    end
  end
LOG

gitlab_rails['rate_limit_unauthenticated_enabled'] = true
gitlab_rails['rate_limit_unauthenticated_requests_per_period'] = 3
gitlab_rails['rate_limit_unauthenticated_period_in_seconds'] = 30

gitlab_rails['rate_limit_authenticated_api_enabled'] = true
gitlab_rails['rate_limit_authenticated_api_requests_per_period'] = 10
gitlab_rails['rate_limit_authenticated_api_period_in_seconds'] = 60

                                                                                                  
