output "sg_alb_id" {
  value = aws_security_group.sg_alb.id
}

output "sg_bastion_id" {
  value = aws_security_group.sg_bastion.id
}

output "sg_nlb_id" {
  value = aws_security_group.sg_nlb.id
}

output "sg_elasticsearch_id" {
  value = aws_security_group.sg_elasticsearch.id
}

output "sg_kibana_id" {
  value = aws_security_group.sg_kibana.id
}

output "sg_logstash_id" {
  value = aws_security_group.sg_logstash.id
}

output "sg_db_id" {
  value = aws_security_group.sg_db.id
}
