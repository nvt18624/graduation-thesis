resource "aws_instance" "default" {
  count         = var.instance_count
  ami           = var.ami_id
  instance_type = var.machine_type
  subnet_id     = var.subnetwork
  key_name      = var.key_name

  associate_public_ip_address = var.enable_public_ip

  private_ip = length(var.internal_ip) > count.index ? var.internal_ip[count.index] : null

  vpc_security_group_ids = var.security_groups

  user_data = var.file_script != "" ? file(var.file_script) : null

  tags = {
    Name = var.instance_count > 1 ? "${var.instance_name}-${count.index}" : var.instance_name
  }
}
