// netowork
network_name = "network_aws"
subnet_2_name = "subnet_2_aws"
subnet_2_range = "10.0.0.0/16"
subnet_2_az = "ap-southeast-1a"
vpc_cidr = "10.0.0.0/16"

//firewall
firewall_name  = "web-sg"
protocol       = "tcp"
ports          = [22, 80, 443, 5044, 5601, 9200]
source_ranges  = ["0.0.0.0/0"]

